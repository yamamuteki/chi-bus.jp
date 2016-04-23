class BusStopsController < ApplicationController
  def index
    @bus_stops = BusStop.where("name like '%#{params[:q]}%'").limit(100)
  end

  def show
    @bus_stop = BusStop.preload(:bus_route_infos).find(params[:id])
    @hash = Gmaps4rails.build_markers(@bus_stop) do |bus_stop, marker|
      marker.lat bus_stop.latitude
      marker.lng bus_stop.longitude
      marker.infowindow bus_stop.name
    end
  end
end
