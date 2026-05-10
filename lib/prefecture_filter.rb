# `ENV["PREFECTURE"]` で BusRoute scope を 1 都道府県に絞るユーティリティ。
#
# stitch:generate / bus_stop_number:generate / bus_stop_number:diagnose で共有して使う。
# 都道府県名 (例: "東京都"、"千葉県") を直接渡す。bus_stops.prefecture は国土数値情報
# の都道府県名がそのまま入っているのでこれと比較する。
#
# 絞り込みアルゴリズム: 該当 prefecture の bus_stops を経由して bus_routes を逆引きする。
# routes 自体には prefecture 列がないため (= 1 路線が複数県を跨ぐケースに対応するため)、
# 「その県のどこかにバス停を持つ route」を対象とする。
#
# 用途: 採番/stitch ロジックの反復実験を 47 倍速で回すためのもの。フィルタが有効な場合
# `db/data/*.csv.gz` の上書きはせず (= 残り 46 県分の出力が消えてしまうため)、ベンチや
# diagnose 専用と割り切る運用にする。
class PrefectureFilter
  # ENV["PREFECTURE"] が指定されていれば scope を絞り、そうでなければ scope をそのまま返す。
  def self.apply(scope)
    return scope unless active?
    pref = ENV["PREFECTURE"]
    filtered = scope.where(id: BusRoute.joins(bus_route_bus_stops: :bus_stop)
                                        .where(bus_stops: { prefecture: pref })
                                        .distinct.select(:id))
    puts "  PREFECTURE=#{pref}: filtered to #{filtered.count} routes"
    filtered
  end

  def self.active?
    ENV["PREFECTURE"].present?
  end
end
