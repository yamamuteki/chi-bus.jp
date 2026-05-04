# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 開発プロセス（最重要）

### Git Flow

- 基本ブランチは `develop`、リリース用が `master`。
- 作業は `develop` から新しいブランチを切る（`feature/*`, `fix/*` などの prefix を用途に応じて使う）。
- ブランチで作業 → push → PR を `develop` 宛で作成。
- **マージはユーザーが手動で行う**。マージ完了の伝達を受けたら、ローカルで `develop` に戻して `git pull`。

### 本番デプロイ

- 本番環境は **Heroku**、`master` ブランチへのマージで **オートデプロイ**される。
- したがって `develop` → `master` の PR マージは「リリース操作そのもの」。マイグレーションの有無、`ENV` 追加、外部 API 呼び出しの増加などの影響範囲を確認したうえで、ユーザーが手動マージする。

### git 操作の確認ルール

- ユーザーは手元で `git diff` を全件レビューしている。**Claude は勝手に `git add` / `commit` / `push` / ブランチ作成 / PR 作成をしない**。
- ファイル編集自体は通常通り行ってよい。git に反映する操作のみ、明示的な依頼があってから実行する。

### コミットメッセージ・PR の言語ルール

- **件名（subject / title）は英語、本文（body / description）は日本語**で書く。コミットメッセージも PR も同じルール。
- 件名は GitHub の一覧画面で読まれるため英語で簡潔に（命令形・先頭大文字、過去のコミット履歴のスタイルを踏襲）。本文は日本語で背景・意図・影響範囲を丁寧に説明する。

## プロジェクト概要

千葉・東京・神奈川・埼玉（および茨城・栃木・群馬の一部）を対象とした、バス停と路線情報を提供する Web サービス（[https://www.chi-bus.jp](https://www.chi-bus.jp)）。

## 開発環境

- Ruby のバージョンは `.ruby-version` で固定。
- 全環境（development / test / production）で **PostgreSQL**。`docker-compose up` で app / db / selenium のコンテナが揃う。`Dockerfile.dev` が development 用、`Dockerfile`（rails new デフォルト）が production 用。
- `kakasi_parser` は Gemfile でコメントアウト中。`keyword:generate`（後述）を走らせる場合のみ有効化が必要。`restore` 系は不要。

## よく使うコマンド

```bash
docker-compose up -d                                       # 開発サーバー（Puma）を常駐起動
docker-compose run --rm app bin/rails db:migrate
docker-compose run --rm app bin/rails test                 # 全テスト
docker-compose run --rm app bin/rails test test/models/bus_stop_test.rb:10
docker-compose run --rm app bin/rails console
docker-compose run --rm app bin/rubocop                    # lint（rubocop-rails-omakase）
docker-compose run --rm app bin/brakeman                   # security scan
```

短時間で完結する操作は `docker-compose run --rm app` で一時コンテナを使うほうが、終了タイミングが明確で常駐コンテナの状態にも干渉しない。Puma を立ち上げて手動確認したいときだけ `docker-compose up -d` を使う。

CI は `.github/workflows/ci.yml`（GitHub Actions）。lint / scan_ruby / scan_js / test の 4 ジョブ構成で、`master` / `develop` への push と全 PR でトリガー。

**`bin/setup` は使わない方が安全**。`bin/setup` は内部で `bin/rails db:setup` を実行し、`db/seeds.rb` 経由で 7 都道府県分の国土数値情報 XML を全パースする極めて重い処理を起動する。新規環境では `bin/rails db:migrate` で空 DB を作るか、シードまで欲しい場合のみ意識的に `bin/rails db:seed` を実行する。

## アーキテクチャ

### ドメインモデル

- `BusStop` — バス停。緯度経度・住所・`keyword`（検索用、後述）。`geocoder` の `reverse_geocoded_by` を設定済み。
- `BusRoute` — 路線。`bus_type` は enum（`private_bus` / `public_bus` / `community_bus` / `demand_bus` / `other`）で、`BUS_TYPE_LABELS` に日本語ラベル。
- `BusRouteBusStop` — 中間テーブル。`bus_stop_number`（路線内での停留所順）を持ち、`BusRoute#bus_route_bus_stops` はこの順にソートされる。
- `BusRouteTrack` — 路線の軌跡（座標列）。`coordinates` は JSON シリアライズ。
- `Place`（`app/models/place.rb`） — ActiveRecord ではなく、Google Places API の結果を `BusStop` 風のインターフェースで包むラッパー。検索 0 件時のフォールバックで使う。

### 検索フロー（`BusStopsController#index`）

1. `params[:q]` あり → `bus_stops.keyword` への `lower(...) LIKE lower(...)` 検索（最大 100 件）。
2. ヒット 0 件 → Google Places API で千葉県庁（35.6049, 140.1208）から半径 50km を検索。結果は `Place` でラップし、`Rails.cache` にクエリ単位でキャッシュ。
3. `params[:position]` あり → `BusStop.near([lat, lng], 20000)` で近傍 12 件。

`BusStopsHelper#bus_stop_or_place_path` で `Place` クリック時のリンクを `?position=lat,lng` に変換しており、これによって「Places フォールバック → クリック → 近傍のバス停一覧」という導線が成立している。

### 検索キーワード

`bus_stops.keyword` は「停留所名 + kakasi で変換したローマ字 + ひらがな + カタカナ」を空白区切りで連結したテキストで、漢字・かな・ローマ字いずれの入力でも `LIKE` でヒットする。生成は `lib/tasks/keyword.rake` の `keyword:generate`（要 `kakasi_parser`）。

### データ構築パイプライン

`db/seeds.rb` は **国土交通省のオープンデータ「国土数値情報」** の XML から全データを構築する：

- `db/N07-11_*.xml` — バス路線（`BusRoute`, `BusRouteTrack`）
- `db/P11-10_*-jgd-g.xml` — バス停（`BusStop`、`BusRoute` との関連付け）

ファイル名末尾 2 桁は JIS 都道府県コード（08〜14 = 茨城〜神奈川）。利用にあたっては国土数値情報ダウンロードサービスの利用規約に従うこと。

シード末尾で 3 つの `restore` タスクを呼び、JSON から派生データを書き戻す：

1. `bus_stop_number:restore` — 路線内での停留所順序（`db/bus_stop_number.json`）
2. `geocode:restore` — 逆ジオコーディング結果（`db/geocording_data.json`）
3. `keyword:restore` — kakasi 変換した検索キーワード（`db/keywords.json`）

各タスクは `generate`（外部 API・kakasi・空間計算など重い処理）→ `dump`（JSON に書き出し）→ `restore`（JSON から DB へ）の 3 段構成。**通常のセットアップ・CI では restore のみで完結し、generate は呼ばない**。`bus_stop_number:generate` は再生成すると順序が変わりうるため、運用上は JSON からの restore が原則。

### テスト

- minitest。`test/test_helper.rb` で `fixtures :all` を有効化してあるので、`test/fixtures/*.yml` は全テストで自動的に読み込まれる。
- controller テストは `ActionDispatch::IntegrationTest`（Rails の現行 generator デフォルト）。`assigns` は使えないので、HTML 構造の検証は `assert_select`、Mock の挙動確認は `Mock#verify` で行う。
- **Google Places のモックは独特**。`test/controllers/bus_stops_controller_test.rb` では `GooglePlaces.send(:remove_const, :Client); GooglePlaces::Client = class_mock` でクラスごと差し替えている。新規テストでも同様のパターンを踏襲するのが無難。
- Geocoder は `Geocoder::Lookup::Test.add_stub(...)` でレスポンスをスタブ可能。`test/test_helper.rb` で `Geocoder.configure(lookup: :test)` してテストモードに固定済み。

### キャッシュ

- production の `cache_store` は明示設定なし（Rails デフォルトの `:memory_store`、プロセスローカル）。dyno 間で共有したくなったら別途検討する。
- ビュー側は `bus_stops/index.html.erb`、`bus_stops/show.html.erb` でフラグメントキャッシュを使用（`cache params[:q].to_s + params[:position].to_s` など）。development でキャッシュ挙動を再現するには `tmp/caching-dev.txt` を `touch` する必要がある。
- Places API のレスポンスもコントローラ側で `Rails.cache.fetch(params[:q])` でキャッシュしている。

### ルーティング

`config/routes.rb` は最小限：`bus_routes#show` / `bus_stops#index,show` / `about#index` / root = `home#index`。

### データベース

- 全環境で PostgreSQL。`config/database.yml` は `RAILS_DATABASE_*` 環境変数で接続先を切り替える形。Heroku では `DATABASE_URL` が優先されるためそちらが効く。
- 検索クエリは `lower(...) like lower(...)` で大文字小文字を吸収（PostgreSQL の `LIKE` が case-sensitive のため）。

### フロントエンド

- アセットパイプラインは Sprockets と propshaft の併用。既存の SCSS / CoffeeScript / jQuery / Bootstrap-sass は Sprockets 経由、新規追加分は propshaft + importmap で扱える状態。
- importmap の entrypoint は `main`（Sprockets の `application.js` と名前衝突しないよう変更済み）。
- Hotwire 系の gem は導入済みだが既存ビューでは未利用。段階的に置き換える前提。

### 外部依存と認証情報

- Google Places / Geocoding API キー — `ENV["GOOGLE_API_KEY"]`。
- **Google Maps JavaScript API キーは `app/views/layouts/application.html.erb` にハードコードされている**（修正候補）。
- Google Analytics トラッカー ID は `config/environments/production.rb` にハードコード。
- New Relic（`newrelic_rpm`）は production で有効。
- `dotenv-rails` で `.env` を読み込み（`.env` は gitignore 済み）。
- CI test job では `GOOGLE_API_KEY: dummy` を渡してモック前提のテストを通している。

### 本番環境の追加設定

- `config.force_ssl = true` で HTTPS 強制。Heroku で独自ドメインを足すときは証明書設定を忘れないこと。
- ログは `RAILS_LOG_TO_STDOUT` が立っていれば STDOUT に出る。Heroku は STDOUT を logplex で集約する前提なので、Heroku 側で `RAILS_LOG_TO_STDOUT=enabled` を設定しておく必要がある。
