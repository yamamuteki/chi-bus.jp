# db:seed は二重取り込みを避けるためのガード。
# 実体のデータ生成は db/data/*.csv で、投入は data:load タスクが行う。
# 国土数値情報の最新 XML を取り込み直したい場合は data:generate タスクを実行する。

if BusStop.exists? || BusRoute.exists? || BusRouteTrack.exists? || BusRouteBusStop.exists?
  puts "Data already loaded. Skipping. Run `bin/rails data:load` to force reload."
else
  Rake::Task["data:load"].invoke
end
