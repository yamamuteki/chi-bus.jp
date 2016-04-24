class BusRouteInfosController < ApplicationController
  def show
    @bus_route_info = BusRouteInfo.preload(:bus_stops).find(params[:id])
    @hash = Gmaps4rails.build_markers(@bus_route_info.bus_stops) do |bus_stop, marker|
      marker.lat bus_stop.latitude
      marker.lng bus_stop.longitude
      marker.infowindow render_to_string partial: 'infowindow', locals: { bus_stop: bus_stop }
    end
    @tracks = @bus_route_info.bus_route.bus_route_tracks.map do |track|
      track.coordinates.map do |coordinate|
        { lat: coordinate[0], lng: coordinate[1] }
      end
    end
  end
end
