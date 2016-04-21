class BusRouteInfosController < ApplicationController
  def show
    @bus_route_info = BusRouteInfo.preload(:bus_stops).find(params[:id])
  end
end
