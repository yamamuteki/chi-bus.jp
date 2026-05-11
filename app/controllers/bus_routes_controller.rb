class BusRoutesController < ApplicationController
  def show
    # fragmented route も直接 URL からは表示する (default_scope を解除)。
    # 一覧/検索からは default_scope で自然と除外される。
    # bus_stops の bus_routes も preload しておく。マーカー title (「○○駅（10）」のような
    # 通過路線数) を build_markers が bus_stop_badge 経由で計算するため、ここで loaded で
    # ないと per-marker で N+1 になる。
    @bus_route = BusRoute.with_fragmented.includes(bus_stops: [ :bus_routes, :bus_route_bus_stops ])
                          .order("bus_route_bus_stops.bus_stop_number").find(params[:id])
  end
end
