# 路線内のバス停の「順番」(BusRouteBusStop#bus_stop_number) を生成・永続化する rake タスク群。
#
# generate: DB 上の路線軌跡 (BusRouteTrack) と停留所座標から空間計算で順序を割り出して DB に書き込む。
# dump:     DB の bus_stop_number を db/bus_stop_number.json に書き出す（永続化）。
# restore:  db/bus_stop_number.json から DB に書き戻す。
#
# generate は計算結果が再現しない（座標の浮動小数点比較や巡回順序に依存して順序が変わりうる）ため、
# 通常のセットアップでは generate ではなく restore を使う、というのが運用ルール。
# CLAUDE.md の「bus_stop_number:generate は再生成すると順序が変わりうるため、運用上は既存 JSON を尊重する原則」を参照。
namespace :bus_stop_number do
  desc "Generate bus stop number"
  task generate: :environment do
    # BusRoute ごとに、その路線の軌跡に沿って近接停留所に 1 から順番を振る。
    progress = ProgressBar.create(title: "Generate", total: BusRoute.count, format: "%t: %J%% |%B|")
    ActiveRecord::Base.transaction do
      # まず既存の番号を全件クリア（中途半端な状態が残っていても再計算できるように）
      BusRouteBusStop.update_all(bus_stop_number: nil)

      BusRoute.find_each do |bus_route|
        index = 0
        bus_route_bus_stops = bus_route.bus_route_bus_stops

        # 軌跡 (Track) を「最初の座標の経度」で並べる。1 路線が複数の Track に分かれている場合に、
        # おおむね西から東へ巡る順序にするための簡易ソート（厳密な進行方向判定はしない）。
        bus_route.bus_route_tracks.sort_by { |t| t.coordinates[0][1] }.each do |track|
          # 軌跡上の各座標について、近くにある未採番の停留所を探して順番を振っていく。
          track.coordinates.each do |coordinate|
            latitude  = coordinate[0]
            longitude = coordinate[1]

            bus_route_bus_stops.each do |bus_route_bus_stop|
              next if bus_route_bus_stop.bus_stop_number # 既に番号が振られた停留所はスキップ

              bus_stop = bus_route_bus_stop.bus_stop
              # 緯度経度をピタゴラス的に二乗距離として比較（厳密な球面距離ではない簡易判定）。
              # 0.000001 ≒ 0.001 度² → 距離としては約 100m 以内（緯度方向は約 111m/度なので妥当）。
              distance = (bus_stop.latitude - latitude) ** 2 + (bus_stop.longitude - longitude) ** 2
              if distance < 0.000001 then
                bus_route_bus_stop.bus_stop_number = index += 1
                bus_route_bus_stop.save
                break # この座標で見つかったら次の軌跡座標へ
              end
            end
          end
        end
        progress.increment
      end
    end
  end

  desc "Dump bus stop number"
  task dump: :environment do
    # DB の BusRouteBusStop を全件走査し、id と bus_stop_number のペアを JSON に書き出す。
    # generate の結果を git にコミット可能な形（db/bus_stop_number.json）で永続化するための工程。
    progress = ProgressBar.create(title: "Dump", total: BusRouteBusStop.count, format: "%t: %J%% |%B|")
    File.write("db/bus_stop_number.json", JSON.pretty_generate(
      BusRouteBusStop.find_each.map do |bus_route_bus_stop|
        progress.increment
        {
          bus_route_bus_stop_id: bus_route_bus_stop.id,
          bus_stop_number: bus_route_bus_stop.bus_stop_number
        }
      end
    ))
  end

  desc "Restore bus stop number"
  task restore: :environment do
    # db/bus_stop_number.json を読み込み、各 BusRouteBusStop の bus_stop_number を復元する。
    # 通常のセットアップでは generate を回さずにこちらを使う（generate は順序が変わりうるため）。
    records = JSON.parse(File.read("db/bus_stop_number.json"))
    progress = ProgressBar.create(title: "Restore", total: records.count, format: "%t: %J%% |%B|")
    ActiveRecord::Base.transaction do
      records.each do |record|
        bus_route_bus_stop = BusRouteBusStop.find record["bus_route_bus_stop_id"]
        bus_route_bus_stop.update(
          bus_stop_number: record["bus_stop_number"]
        )
        progress.increment
      end
    end
  end
end
