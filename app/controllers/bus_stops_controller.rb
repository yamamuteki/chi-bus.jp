class BusStopsController < ApplicationController
  def index
    session[:q] = params[:q]
    @bus_stops = []
    if params[:q] then
      @bus_stops = BusStop.where("name like '%#{params[:q]}%'").order('name, latitude DESC').limit(100)
    elsif params[:position]
      latitude = params[:position].split(',')[0].to_f
      longitude = params[:position].split(',')[1].to_f
      @bus_stops = BusStop.near([latitude, longitude], 20000).limit(25)
    end
  end

  def show
    @bus_stop = BusStop.preload(bus_route_infos: [bus_route: [:bus_route_tracks]]).find(params[:id])
  end
end
