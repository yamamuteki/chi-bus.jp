# chi-bus.jp

全国 47 都道府県のバス停と路線情報を提供する Web サービスです。

- [https://www.chi-bus.jp](https://www.chi-bus.jp)
- [ERD](./erd.pdf)

## 環境変数

- `GOOGLE_PLACES_API_KEY` — Google Places API のキー（検索 0 件時のフォールバック用、サーバーサイド呼び出し）
- `GOOGLE_MAPS_API_KEY` — Google Maps JavaScript API のキー（地図表示用、HTML に埋め込まれるためリファラ制限を推奨）
- `GA_TRACKER_ID` — Google Analytics トラッカー ID（production のみ。未設定なら計測しない）
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

バス停・路線データは `db/data/*.csv.gz` として git 管理されており、`db:seed` で PostgreSQL の `COPY` 経由で投入します。約 1 分以内で完了します。

```
docker compose run --rm app bin/rails db:seed
```

`db/seeds.rb` は二重取り込みガード付きで、データ未投入のときだけ取り込みを走らせ、すでに入っていればスキップします。

## Docker での ERD 生成

```
docker compose run --rm app bundle exec erd
```

## Heroku でのデプロイ

本番環境は Heroku で、`master` ブランチへの push をトリガーにオートデプロイされます。`develop` で開発し、リリース時に `master` へマージしてください。

DB セットアップとキャッシュクリアは buildpack 方式で行います。`gunpowderlabs/buildpack-ruby-rake-deploy-tasks` が `DEPLOY_TASKS` 環境変数に列挙した rake task を build phase で実行するため、出力は build log に流れて Heroku Activity / GitHub の Deployment 画面から確認できます。`db:prepare` は fresh DB なら `schema:load` + `seed`（`db/seeds.rb` のガード経由で `data:load` が呼ばれて `db/data/*.csv.gz` を `COPY` 投入）まで自動で走り、既存 DB では `migrate` のみ実行されます。

初回セットアップが必要な場合：

1. Heroku アカウントを作成し、Heroku web console でアプリを作成
2. `heroku login`
3. Heroku Postgres アドオンを追加
4. config vars に `GOOGLE_PLACES_API_KEY`、`GOOGLE_MAPS_API_KEY`、`GA_TRACKER_ID`、`SECRET_KEY_BASE`、`RAILS_LOG_TO_STDOUT=enabled`、`RAILS_SERVE_STATIC_FILES=enabled` などを設定
5. heroku CLI を対象アプリに関連付ける（以降の `heroku` コマンドで `-a <app名>` を毎回指定しなくて済む。デプロイ自体は GitHub 連携経由なのでこの remote 経由で push する必要はない）：

   ```
   heroku git:remote -a <app名>
   ```

6. buildpack と `DEPLOY_TASKS` を設定する：

   ```
   heroku buildpacks:set https://github.com/heroku/heroku-buildpack-ruby
   heroku buildpacks:add https://github.com/gunpowderlabs/buildpack-ruby-rake-deploy-tasks
   heroku config:set DEPLOY_TASKS='db:prepare cache:clear'
   ```

7. GitHub 連携を有効化して `master` ブランチの自動デプロイを ON
