class BusRoutesController < ApplicationController
  def show
    @bus_route = BusRoute.includes(bus_stops: [:bus_route_bus_stops]).order('bus_route_bus_stops.bus_stop_number').find(params[:id])
  end
end
