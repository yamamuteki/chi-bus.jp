class BusStopsController < ApplicationController
  def index
    if params[:q] then
      @bus_stops = BusStop.preload(:bus_routes).where("name like '%#{params[:q]}%'").order('name, latitude DESC').limit(100)
    elsif params[:position]
      latitude = params[:position].split(',')[0].to_f
      longitude = params[:position].split(',')[1].to_f
      @bus_stops = BusStop.preload(:bus_routes).near([latitude, longitude], 20000).limit(12)
    else
      @bus_stops = []
    end
  end

  def show
    @bus_stop = BusStop.preload(bus_routes: [:bus_stops, :bus_route_tracks]).find(params[:id])
  end
end
