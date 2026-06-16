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

### リリース手順

1. develop が安定していることを確認
2. develop の HEAD に **軽量タグ** を打つ: `git tag vX.Y.Z develop` (`-a -m` は付けない。過去のタグも全て lightweight)
3. タグを push: `git push origin vX.Y.Z`
4. GitHub UI でそのタグから Release を作成 (リリースノートはここで書く)
5. develop → master の PR を作成・マージ → master push が Heroku オートデプロイをトリガ

タグを develop 側に打つのは「master マージ前にバージョンを確定させたい」「Heroku が master push を契機にデプロイするので確定状態にしたい」ため。一般的な「master のマージコミットに打つ」フローからはずれるが、master のマージコミットからもタグは到達できるので checkout / hotfix 起点には支障なし。

### git 操作の確認ルール

- ユーザーは手元で `git diff` を全件レビューしている。**Claude は勝手に `git add` / `commit` / `push` / PR 作成をしない**。
- ファイル編集およびブランチ作成は通常通り行ってよい。git に反映する操作（add / commit / push / PR）のみ、明示的な依頼があってから実行する。
- **`develop` と `master` に直接 commit / push しない**。「コミット」「PR 作成」を依頼されたら、まず `git branch --show-current` で現在のブランチを確認し、`develop` または `master` にいたら **add / commit より前に** `git checkout -b <prefix>/<name>` で作業ブランチを切る。過去複数回この手順を飛ばして develop に直接 commit しかけているので、最初のブランチ確認は省略禁止。マージは必ず PR 経由 (本人手動マージ) で行う。

### コミットメッセージ・PR の言語ルール

- **件名（subject / title）は英語、本文（body / description）は日本語**で書く。コミットメッセージも PR も同じルール。
- 件名は GitHub の一覧画面で読まれるため英語で簡潔に（命令形・先頭大文字、過去のコミット履歴のスタイルを踏襲）。本文は日本語で背景・意図・影響範囲を丁寧に説明する。

## プロジェクト概要

全国 47 都道府県のバス停と路線情報を提供する Web サービス（[https://www.chi-bus.jp](https://www.chi-bus.jp)）。元々は千葉県を対象に開発・運用しており、サービス名 (chi-bus.jp) や「チーバくん」マスコット、about ページ内の動機・許諾節は千葉発の名残で意図的に残している。対応エリアの記述だけが全国向けに更新されている。

## 開発環境

- Ruby のバージョンは `.ruby-version` で固定。
- 全環境（development / test / production）で **PostgreSQL**。`docker-compose up` で app / db / selenium のコンテナが揃う。`Dockerfile.dev` が development 用、`Dockerfile`（rails new デフォルト）が production 用。
- `keyword:generate` (後述) は `libkakasi.so.2` を要求する。`Dockerfile.dev` に kakasi コマンドを入れているのでランタイム共有ライブラリも一緒に入る。`lib/kakasi.rb` から FFI で attach する。

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
2. ヒット 0 件 → Google Places API で千葉県庁（35.6049, 140.1208）から半径 50km を検索。結果は `Place` でラップし、`Rails.cache` にクエリ単位でキャッシュ。検索中心と半径は千葉発時代の名残で、全国対応後の現在は関東外ユーザーからは届かない既知の罠 (改善候補)。
3. `params[:position]` あり → `BusStop.near([lat, lng], 20000)` で近傍 12 件。

`BusStopsHelper#bus_stop_or_place_path` で `Place` クリック時のリンクを `?position=lat,lng` に変換しており、これによって「Places フォールバック → クリック → 近傍のバス停一覧」という導線が成立している。

### 検索キーワード

`bus_stops.keyword` は「停留所名 + kakasi で変換したローマ字 + ひらがな + カタカナ」を空白区切りで連結したテキストで、漢字・かな・ローマ字いずれの入力でも `LIKE` でヒットする。生成は `lib/tasks/keyword.rake` の `keyword:generate`。kakasi の内部エンコーディング (CP932) で表現できない希少漢字を含む停留所名 (47 都道府県分で 22 件) は変換失敗するため、`begin/rescue` で `bus_stop.name` 単体にフォールバックする。kakasi の呼び出しは `lib/kakasi.rb` (FFI で `libkakasi.so.2` を attach、元 `kakasi` gem の代替) と `lib/kakasi_parser.rb` (元 `kakasi_parser` gem のポート、`{a|b}` 形式の曖昧読み候補を直積で展開) に分離。

### 派生データの計算ロジック (`lib/`)

`bus_stop_number` / `city` / `formatted_address` は KSJ ソース (N07 / P11) に含まれないため、各 `*:generate` タスクが `lib/` 配下の PORO を呼んで計算し CSV に書き出す。後段の `*:load` が DB に bulk UPDATE する (各列が独立に更新できる構造)。

- `lib/track_stitcher.rb` — 路線の `bus_route_tracks`（複数 Curve segment）を 1 本のフラット座標列につなぐ。`bus_stop_number:generate` の前段。
- `lib/bus_stop_numberer.rb` — flat_coords にバス停を投影し、曲線位置で並べて `bus_stop_number` を割り当て。
- `lib/line_name_orienter.rb` — `line_name` の地名ヒント (「○○行」「○○方面」) で進行方向を推定し、stitch 結果の向きを補正。
- `lib/isj_reverse_geocoder.rb` — 国土交通省「位置参照情報」(ISJ) から (lat, lng) → (city, formatted_address) を引く PORO。grid bucket + 半径フォールバックで近傍検索。`geocode:generate` 専用 (旧 Google Geocoding API 依存を撤廃した置き換え)。

### データ構築パイプライン

データは KSJ (国土数値情報 N07/P11) と ISJ (位置参照情報) を source of truth とし、いずれもメンテナンス終了済みで **forever immutable**。アプリ内でも create / update は発生しないので、CSV が再生成されるのはロジック変更時 (numberer / orienter / stitcher / fragmented 判定の見直し等) のみ。

ソース:

- `db/ksj/n07/N07-11_*.xml.gz` — バス路線 (国土数値情報、ファイル名末尾 2 桁が JIS 都道府県コード)
- `db/ksj/p11/P11-10_*-jgd-g.xml.gz` — バス停
- `db/isj/{prefcode}-18.0b/*.csv` — 位置参照情報 (CP932 エンコード)

利用にあたっては国土数値情報・位置参照情報ダウンロードサービスの利用規約に従うこと。

#### 罠と非自明な決定

- **gzip 圧縮の理由**: `keywords.csv` が生 270MB あり GitHub の 100MB ファイル上限を超える。全 CSV を `.csv.gz` で揃え、`Zlib::GzipReader` 経由で `COPY FROM STDIN` に流し込む。
- **`stitches.csv.gz` だけ git 管理外** (`.gitignore`): TrackStitcher の per-route キャッシュで production 不要、31 MB のサイズだけが負担。採番反復前に 1 度だけ `stitch:generate` をローカルで走らせる必要がある (~70s)。
- **N07 の Curve は県境で両県 XML に重複登録されている**: 過去 dedup を試したが「別 route の偶然同じ座標 (高速バス共有区間や折返便の住宅街共有区間)」まで巻き込んで curves が大量喪失していたため no-dedup に切り替え済み。`bus_route_tracks` 行数は +36% 増えるが採番が完全になる。
- **派生列は独立**: `bus_stop_number` / `city` / `formatted_address` / `keyword` は別 CSV / 別 `*:load` で bulk UPDATE する。1 つを再生成しても他に影響しない構造。

#### タスク

生成 (`*:generate`) は CSV を出力するだけで DB を触らない。ロード (`*:load`) が CSV → DB に bulk UPDATE する。

- `data:generate` — N07 / P11 XML → `bus_routes` / `bus_route_tracks` / `bus_stops` / `bus_route_bus_stops` の 4 CSV
- `stitch:generate` — TrackStitcher のキャッシュ (ローカル専用)
- `bus_stop_number:generate` — numberer + orienter で採番 (`stitches.csv.gz` が前提、無いと raise)
- `geocode:generate` — ISJ から (city, formatted_address)
- `keyword:generate` — kakasi で検索キーワード (`libkakasi.so.2` 必須)
- `data:load` — `*_csv.gz` 4 つを `TRUNCATE` + `COPY FROM STDIN` で投入。派生列は NULL のまま入る
- `bus_stop_number:load` / `geocode:load` / `keyword:load` — 対応する CSV を bulk UPDATE
- `db:seed` — 二重取り込みガード経由で `data:load` → `bus_stop_number:load` → `geocode:load` → `keyword:load` を順に呼ぶ。Heroku でも約 1 分。新規セットアップはこれだけで完成

#### 診断 / プロファイル

- `bus_stop_number:diagnose` — 採番品質指標 (idx_inversions / anomaly_jumps / off_track / backward_turns 他) を `tmp/bus_stop_number_diagnostics.csv` に出力。`tmp/chi-bus-baseline/` のベースラインと diff してロジック変更の影響を測る運用。`INCLUDE_FRAGMENTED=1` で fragmented 路線も含む
- `bus_stop_number:inspect ROUTE_ID=N` — 1 路線分の tracks / 起点選択 / stitch_steps / 各バス停の closest_idx を標準出力にダンプ。diagnose で異常値が出た路線の深掘り用
- `*:profile` — stackprof で `:generate` を計測し `tmp/*.stackprof` 出力

`PREFECTURE=東京都` を `stitch:generate` / `bus_stop_number:generate` / `bus_stop_number:diagnose` に渡すと該当県のみ計算 (反復フィードバック高速化)。`data:generate` には適用しない (ID 採番が壊れる)、`geocode:generate` / `keyword:generate` は反復頻度が低く ROI 無し。

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

- Google Places API キー — `ENV["GOOGLE_PLACES_API_KEY"]`。検索ヒット 0 件時のフォールバックでのみ使う。Geocoding は ISJ オフラインデータ (`lib/isj_reverse_geocoder.rb`) に移行したため Google Geocoding API は使っておらず、`config/initializers/geocoder.rb` も api_key 未設定。
- Google Maps JavaScript API キー — `ENV["GOOGLE_MAPS_JS_API_KEY"]` (`app/views/layouts/application.html.erb`)。HTML に埋め込まれるためリファラ制限前提。Places 用と分けてあるのは公開面 (Maps) と非公開面 (Places) で Google Cloud 側の制限ポリシーが違うため。ENV 名を `MAPS_JS` まで詳細にしているのは Google Maps Platform にサーバーサイド製品 (Geocoding / Directions / Distance Matrix / Maps Static など) も多数あり、将来追加した時に用途が一目で分かるようにするため。
- Google Analytics 4 Measurement ID — `ENV["GA_TRACKER_ID"]` (`app/views/layouts/application.html.erb`)。GA4 公式の `gtag.js` スニペットを直書きしている。`Rails.env.production?` かつ ENV が present のときだけタグを出力するので dev / test では何も出ない。`google-analytics-rails` gem は GA4 (gtag.js) 非対応なので撤去済み。
- New Relic（`newrelic_rpm`）は production で有効。
- `dotenv-rails` で `.env` を読み込み（`.env` は gitignore 済み）。
- CI test job では `GOOGLE_PLACES_API_KEY: dummy` を渡してモック前提のテストを通している。

### 本番環境の追加設定

- `config.force_ssl = true` で HTTPS 強制。Heroku で独自ドメインを足すときは証明書設定を忘れないこと。
- ログは `RAILS_LOG_TO_STDOUT` が立っていれば STDOUT に出る。Heroku は STDOUT を logplex で集約する前提なので、Heroku 側で `RAILS_LOG_TO_STDOUT=enabled` を設定しておく必要がある。
