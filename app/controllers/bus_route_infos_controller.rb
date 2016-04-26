class BusRouteInfosController < ApplicationController
  def show
    @bus_route_info = BusRouteInfo.preload([:bus_stops, bus_route: [:bus_route_tracks]]).find(params[:id])
  end
end
