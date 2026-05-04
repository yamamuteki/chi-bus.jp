# chi-bus.jp [![Build Status](https://travis-ci.org/yamamuteki/chi-bus.jp.svg?branch=master)](https://travis-ci.org/yamamuteki/chi-bus.jp) [![Coverage Status](https://coveralls.io/repos/github/yamamuteki/chi-bus.jp/badge.svg?branch=master)](https://coveralls.io/github/yamamuteki/chi-bus.jp?branch=master) [![Code Climate](https://codeclimate.com/github/yamamuteki/chi-bus.jp/badges/gpa.svg)](https://codeclimate.com/github/yamamuteki/chi-bus.jp)

千葉・東京・神奈川・埼玉（および茨城・栃木・群馬の一部）を対象とした、バス停と路線情報を提供する Web サービスです。

- [https://www.chi-bus.jp](https://www.chi-bus.jp)
- [ERD](./erd.pdf)

## 環境変数

- `GOOGLE_API_KEY` — Google Places / Geocoding API のキー
- `RAILS_DATABASE_HOST`
- `RAILS_DATABASE_PORT`
- `RAILS_DATABASE_USER`
- `RAILS_DATABASE_PASSWORD`
- `SECRET_KEY_BASE` — production のみ
- `RAILS_LOG_TO_STDOUT` — production で STDOUT にログ出力する場合に設定（Heroku 推奨）
- `RAILS_SERVE_STATIC_FILES` — production で `public/` 配下を Rails から配信する場合に設定

`.env` を作成すれば `dotenv-rails` が読み込みます（`.env` は git 管理対象外）。

## Docker での開発環境セットアップ

1. `docker compose up`
2. http://localhost:3000 を開く

初回起動時は `bin/entry` が `bundle install` → `db:create` → `db:migrate` を実行します。空 DB で起動するため、バス停・路線データが必要な場合は別途シードを実行してください（後述）。

## Docker でのテスト実行

```
docker compose run --rm app rails test
```

## Docker でのデータ投入

バス停・路線データは `db/data/*.csv` として git 管理されており、PostgreSQL の `COPY` 経由で投入します。約 1 分以内で完了します。

```
docker compose run --rm app bin/rails data:load
```

`db/seeds.rb` は二重取り込みガードのみで、データ未投入なら自動的に `data:load` を呼びます。すでにデータが入っていればスキップします。

```
docker compose run --rm app bin/rails db:seed
```

国土交通省「国土数値情報」の XML を最新版に差し替えてデータを再生成したい場合は `data:generate` で `db/data/*.csv` を更新します（重い処理、ローカルで実行して結果を git にコミット）。

```
docker compose run --rm app bin/rails data:generate
```

## Docker での ERD 生成

```
docker compose run --rm app bundle exec erd
```

## Heroku でのデプロイ

本番環境は Heroku で、`master` ブランチへの push をトリガーにオートデプロイされます。`develop` で開発し、リリース時に `master` へマージしてください。

`Procfile` の `release` フェーズで `bin/rails db:prepare` が走り、初回デプロイなら `db:create` + `db:schema:load` + `db:seed`（`db/seeds.rb` のガード経由で `data:load` が呼ばれて `db/data/*.csv` を `COPY` 投入）、2 回目以降なら `db:migrate` のみが実行されます。

初回セットアップが必要な場合：

1. Heroku アカウントを作成し、Heroku web console でアプリを作成
2. `heroku login`
3. Heroku Postgres アドオンを追加
4. config vars に `GOOGLE_API_KEY`、`SECRET_KEY_BASE`、`RAILS_LOG_TO_STDOUT=enabled`、`RAILS_SERVE_STATIC_FILES=enabled` などを設定
5. GitHub 連携を有効化して `master` ブランチの自動デプロイを ON
