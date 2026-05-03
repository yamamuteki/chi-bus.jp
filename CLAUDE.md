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

千葉・東京・神奈川・埼玉（および茨城・栃木・群馬の一部）を対象とした、バス停と路線情報を提供する Web サービス（[https://www.chi-bus.jp](https://www.chi-bus.jp)）。Rails 5.0 / Ruby 2.6.10。フロントは CoffeeScript + SCSS、Bootstrap (`bootstrap-sass`) + jQuery + Turbolinks 構成。地図表示は `gmaps4rails`。

## 開発環境

- Ruby は `.ruby-version` の **2.6.10 固定**（Gemfile も `~> 2.6.10`）。
- `.bundle/config` に `BUNDLE_WITHOUT: "production"` があるので、ローカルで `bundle install` すると `pg` などの production gem は入らない。
- ネイティブ拡張は arm64-darwin × Ruby 2.6 のため `ffi ~> 1.16.3` / `nio4r ~> 2.5.9` にピン留めされている。Gemfile を弄るときはこの制約を壊さない。
- `kakasi_parser` は Gemfile でコメントアウト中。`keyword:generate`（後述）を走らせる場合のみ有効化が必要。`restore` 系は不要。

## よく使うコマンド

```bash
bundle install                              # production グループは自動除外
bin/rails db:migrate                        # マイグレーション
bin/rails db:migrate RAILS_ENV=test         # テスト DB の準備（CI と同じ）
bin/rails test                              # 全テスト（minitest）
bin/rails test test/models/bus_stop_test.rb # 単一ファイル
bin/rails test test/models/bus_stop_test.rb:10  # 特定行
bin/rails server                            # 開発サーバー（Puma）
bin/rails console
```

CI（`.travis.yml`）は `db:migrate RAILS_ENV=test` → `bin/rails test`。Rubocop は `.rubocop.yml` で `LineLength: 120` のみ設定。

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
- カバレッジは SimpleCov + Coveralls で計測。テストレポートは `minitest-reporters` 経由。
- **Google Places のモックは独特**。`test/controllers/bus_stops_controller_test.rb` では `GooglePlaces.send(:remove_const, :Client); GooglePlaces::Client = class_mock` でクラスごと差し替えている。新規テストでも同様のパターンを踏襲するのが無難。
- Geocoder は `Geocoder::Lookup::Test.add_stub(...)` でレスポンスをスタブ可能。

### キャッシュ

- production は Redis（`config.cache_store = :redis_store, ENV["REDIS_URL"]`、`redis-rails` gem）。
- development はデフォルト `:null_store`。`tmp/caching-dev.txt` を作ると `:memory_store` が有効化される。
- ビュー側は `bus_stops/index.html.erb`、`bus_stops/show.html.erb` でフラグメントキャッシュを使用（`cache params[:q].to_s + params[:position].to_s` など）。development でキャッシュ挙動を再現するには上記の touch が必要。
- Places API のレスポンスもコントローラ側で `Rails.cache.fetch(params[:q])` でキャッシュしている。

### ルーティング

`config/routes.rb` は最小限：`bus_routes#show` / `bus_stops#index,show` / `about#index` / root = `home#index`。

### データベース

- development / test は SQLite3。
- production は PostgreSQL（`pg` gem）だが、**`config/database.yml` の production セクションは SQLite のまま放置されている**。Heroku が `DATABASE_URL` 環境変数で設定をオーバーライドするため動作はするが、ローカルで production モードを再現したい場合は database.yml の修正が必要になる点に注意。
- SQLite（dev/test）と PostgreSQL（prod）の挙動差に注意。`LIKE` は PostgreSQL では case-sensitive なので検索クエリは `lower(...) like lower(...)` で吸収している。型キャストや enum 周りでも差が出やすい。

### 外部依存と認証情報

- Google Places API / Google Geocoding API キー — `Rails.application.secrets.google_api_key`（`config/secrets.yml` 経由、`ENV["GOOGLE_API_KEY"]` から読み込み）。
- **Google Maps JavaScript API キーは `app/views/layouts/application.html.erb` にハードコードされている**（修正候補）。
- Google Analytics トラッカー ID（`UA-544999-5`）は `config/environments/production.rb` にハードコード。
- New Relic（`newrelic_rpm`）、Coveralls、Code Climate に連携。
- `dotenv-rails` で `.env` を読み込み（`.env` は gitignore 済み）。

### 本番環境の追加設定

- `config.force_ssl = true` で HTTPS 強制。Heroku で独自ドメインを足すときは証明書設定を忘れないこと。
- ログは `RAILS_LOG_TO_STDOUT` が立っていれば STDOUT に出る。Heroku は STDOUT を logplex で集約する前提なので、Heroku 側で `RAILS_LOG_TO_STDOUT=enabled` を設定しておく必要がある。
