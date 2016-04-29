class BusRoutesController < ApplicationController
  def show
    @bus_route = BusRoute.preload(:bus_route_tracks, bus_stops: [:bus_routes]).find(params[:id])
  end
end
