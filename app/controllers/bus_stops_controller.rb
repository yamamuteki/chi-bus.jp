class BusStopsController < ApplicationController
  def index
    @bus_stops = BusStop.where("name like '%#{params[:q]}%'").limit(100)
    @hash = Gmaps4rails.build_markers(@bus_stops) do |bus_stop, marker|
      marker.lat bus_stop.latitude
      marker.lng bus_stop.longitude
      marker.infowindow render_to_string partial: 'infowindow', locals: { bus_stop: bus_stop }
    end
  end

  def show
    @bus_stop = BusStop.preload(:bus_route_infos).find(params[:id])
    @hash = Gmaps4rails.build_markers(@bus_stop) do |bus_stop, marker|
      marker.lat bus_stop.latitude
      marker.lng bus_stop.longitude
      marker.infowindow render_to_string partial: 'infowindow', locals: { bus_stop: bus_stop }
    end
  end
end
