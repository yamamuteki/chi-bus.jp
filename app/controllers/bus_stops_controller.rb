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
    @bus_stop = BusStop.preload(bus_route_infos: [bus_route: [:bus_route_tracks]]).find(params[:id])
    @hash = Gmaps4rails.build_markers(@bus_stop) do |bus_stop, marker|
      marker.lat bus_stop.latitude
      marker.lng bus_stop.longitude
      marker.infowindow render_to_string partial: 'infowindow', locals: { bus_stop: bus_stop }
    end
    @tracks = @bus_stop.bus_route_infos.flat_map do |info|
      info.bus_route.bus_route_tracks.map do |track|
        track.coordinates.map do |coordinate|
          { lat: coordinate[0], lng: coordinate[1] }
        end
      end
    end
  end
end
