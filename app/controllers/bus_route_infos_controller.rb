class BusRouteInfosController < ApplicationController
  def show
    @bus_route_info = BusRouteInfo.preload(:bus_stops).find(params[:id])
    @hash = Gmaps4rails.build_markers(@bus_route_info.bus_stops) do |bus_stop, marker|
      marker.lat bus_stop.latitude
      marker.lng bus_stop.longitude
      marker.infowindow bus_stop.name
    end
  end
end
