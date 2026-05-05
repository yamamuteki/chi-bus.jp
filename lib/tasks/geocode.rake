# バス停の住所情報（郵便番号・市区町村・整形済み住所）を Google の逆ジオコーディング API で取得し、
# DB と JSON に永続化する rake タスク群。
#
# generate: Google API を呼んで BusStop に住所情報を埋める（外部 API 課金が発生する重い処理）。
# dump:     DB の住所情報を db/geocording_data.json に書き出す（永続化）。
# restore:  db/geocording_data.json から DB に書き戻す。
#
# 通常のセットアップでは generate ではなく restore を使う（API コスト・実行時間の節約）。
namespace :geocode do
  desc "Generate geocording data"
  task generate: :environment do
    # formatted_address が未設定の停留所のみ対象。これにより:
    # - 初回セットアップ時は全件処理
    # - 中断 → 再実行時は未処理分から続けられる
    # - 既存停留所への再実行（API 二重課金）を防げる
    query = BusStop.where(formatted_address: nil)
    progress = ProgressBar.create(title: "Generate", total: query.count, format: "%t: %J%% |%B|")
    query.find_each.each do |bus_stop|
      # Geocoder gem の reverse_geocode が、緯度経度を逆引きして
      # postal_code / city / formatted_address を埋めてくれる。
      # 対応マッピングは BusStop モデルの reverse_geocoded_by ブロックを参照。
      bus_stop.reverse_geocode
      bus_stop.save!
      progress.increment
    end
  end

  desc "Dump geocording data"
  task dump: :environment do
    # DB の住所情報を JSON に書き出して永続化する。
    # generate の結果を git にコミット可能な形にして、運用時は restore で再現する。
    progress = ProgressBar.create(title: "Dump", total: BusStop.count, format: "%t: %J%% |%B|")
    File.write("db/geocording_data.json", JSON.pretty_generate(
      BusStop.find_each.map do |bus_stop|
        progress.increment
        {
          bus_stop_id: bus_stop.id,
          postal_code: bus_stop.postal_code,
          city: bus_stop.city,
          formatted_address: bus_stop.formatted_address
        }
      end
    ))
  end

  desc "Restore geocording data"
  task restore: :environment do
    # db/geocording_data.json を読み込み、各 BusStop の住所情報を復元する。
    # 通常のセットアップではこちらを使い、Google API への問い合わせを避ける。
    records = JSON.parse(File.read("db/geocording_data.json"))
    progress = ProgressBar.create(title: "Restore", total: records.count, format: "%t: %J%% |%B|")
    ActiveRecord::Base.transaction do
      records.each do |record|
        bus_stop = BusStop.find record["bus_stop_id"]
        bus_stop.update(
          postal_code: record["postal_code"],
          city: record["city"],
          formatted_address: record["formatted_address"]
        )
        progress.increment
      end
    end
  end
end
