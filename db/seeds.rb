# db:seed は二重取り込みを避けるためのガード。
# 実体のデータ生成は db/data/*.csv で、投入は data:load タスクが行う。
# 国土数値情報の最新 XML を取り込み直したい場合は data:generate タスクを実行する。

if BusStop.exists? || BusRoute.exists? || BusRouteTrack.exists? || BusRouteBusStop.exists?
  puts "Data already loaded. Skipping. Run `bin/rails data:load` to force reload."
else
  Rake::Task["data:load"].invoke
  # bus_route_bus_stops.csv / bus_stops.csv の派生列は data:generate では NULL のまま出力される。
  # 各 load タスクが対応する CSV (db/data/*.csv) から bulk UPDATE で値を埋める。
  Rake::Task["bus_stop_number:load"].invoke
  Rake::Task["geocode:load"].invoke
  Rake::Task["keyword:load"].invoke
end
