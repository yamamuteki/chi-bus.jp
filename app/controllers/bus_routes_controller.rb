class BusRoutesController < ApplicationController
  def show
    # fragmented route も直接 URL からは表示する (default_scope を解除)。
    # 一覧/検索からは default_scope で自然と除外される。
    @bus_route = BusRoute.with_fragmented.includes(bus_stops: [ :bus_route_bus_stops ])
                          .order("bus_route_bus_stops.bus_stop_number").find(params[:id])
  end
end
