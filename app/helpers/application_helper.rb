module ApplicationHelper
  def build_markers(bus_stops, position = nil)
    hash = Gmaps4rails.build_markers(bus_stops) do |bus_stop, marker|
      marker.lat bus_stop.latitude
      marker.lng bus_stop.longitude
      marker.infowindow render partial: 'infowindow', locals: { bus_stop: bus_stop }
    end
    if position then
      hash + Gmaps4rails.build_markers([position]) do |bus_stop, marker|
        marker.lat position.split(',')[0]
        marker.lng position.split(',')[1]
        marker.picture({ url: image_path('bluedot.png'), width: '34', height: '34' })
      end
    end
  end
  def build_routes_hash(bus_route_infos)
    tracks = bus_route_infos.flat_map do |info|
      info.bus_route.bus_route_tracks.map do |track|
        track.coordinates.map do |coordinate|
          { lat: coordinate[0], lng: coordinate[1] }
        end
      end
    end
  end
end
