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
- DB セットアップとキャッシュクリアは buildpack 方式（`gunpowderlabs/buildpack-ruby-rake-deploy-tasks`）で実行する。`DEPLOY_TASKS='db:prepare cache:clear'` を build phase の最後に走らせる構成。release phase ではなく build phase に寄せたのは、release phase の失敗が build log に出ず GitHub オートデプロイ運用では見落としやすかったため（`Procfile` は使わない）。
- 罠: `db:prepare` は **fresh DB（schema_migrations が空）のときだけ** schema:load + seed を回し、既存 DB では migrate しか走らない。データを完全に投入し直したいときはテーブル定義ごと吹き飛ばす必要があるので `heroku pg:reset DATABASE` を使う。
- したがって `develop` → `master` の PR マージは「リリース操作そのもの」。マイグレーションの有無、`ENV` 追加、外部 API 呼び出しの増加などの影響範囲を確認したうえで、ユーザーが手動マージする。
- セットアップ手順とコマンドは `README.md` の「Heroku でのデプロイ」節を参照。

### git 操作の確認ルール

- ユーザーは手元で `git diff` を全件レビューしている。**Claude は勝手に `git add` / `commit` / `push` / PR 作成をしない**。
- ファイル編集およびブランチ作成は通常通り行ってよい。git に反映する操作（add / commit / push / PR）のみ、明示的な依頼があってから実行する。

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

新規環境では `bin/rails db:seed` でデータが未投入なら自動的に `data:load` が走り、`db/data/*.csv.gz` から PostgreSQL の `COPY` で 1 分以内に投入される。

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

XML + JSON のソースから `db/data/*.csv.gz` を生成し、gzip 圧縮した CSV を PostgreSQL の `COPY FROM STDIN` で投入する 2 段構成。圧縮しているのは GitHub の 100MB ファイル上限を超える `keywords.csv` (生で 270MB) を git 管理するため。load 側は `Zlib::GzipReader` で逐次解凍しながら `put_copy_data` する。

ソース：

- `db/ksj/n07/N07-11_*.xml.gz` — バス路線（**国土交通省「国土数値情報」**、ファイル名末尾 2 桁は JIS 都道府県コード、47 都道府県分）。生 XML が大きいので gzip 圧縮して git 管理 (`open_xml` で透過解凍)。県境を跨ぐ Curve は隣県 N07 にも同一座標で重複登録されているため `data:generate` 側で座標 hash dedup している
- `db/ksj/p11/P11-10_*-jgd-g.xml.gz` — バス停（47 都道府県分）
- `db/isj/{prefcode}-18.0b/*.csv` — **位置参照情報** (大字・町丁目レベル、CP932 エンコード)。reverse geocoding (lat/lng → 住所) のソース。47 都道府県分。XML 同様 git 管理 (約 17MB)。最新版を取り込み直すときは <https://nlftp.mlit.go.jp/cgi-bin/isj/dls/_choose_method.cgi> から DL し直す。zip / html / xml は不要なので CSV だけ残す運用。

利用にあたっては国土数値情報・位置参照情報ダウンロードサービスの利用規約に従うこと。

タスク：

- `data:generate` — XML をパースし、`db/data/*.csv.gz` を出力する。重い処理なのでローカルで実行し、結果を git にコミットして運用する。最新の国土数値情報 XML に差し替えたいときに走らせる。
- `data:load` — `db/data/*.csv.gz` を `COPY FROM STDIN` で DB に流し込む。Heroku でも実行可能で約 1 分。`db/seeds.rb` のガード経由で `bin/rails db:seed` から呼ばれるルートと、直接 `bin/rails data:load` で呼ぶルートの両方がある。
- `bus_stop_number:generate` — `db/data/bus_stop_numbers.csv.gz` を生成。重い処理だが結果を git に commit するので CI / 通常セットアップでは load のみ呼べばよい。
- `geocode:generate` — `db/isj/` の ISJ CSV を読み、各 bus_stop の最近接 entry から `db/data/geocoding.csv.gz` (city, formatted_address) を生成。所要 10 秒程度。ISJ raw データ (db/isj/) はダウンロード必要、生成 CSV だけ commit する。
- `keyword:generate` — kakasi で `db/data/keywords.csv.gz` を生成 (kakasi gem 要)。
- 各 `*:load` — 対応する CSV を bulk UPDATE で DB に投入。

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
