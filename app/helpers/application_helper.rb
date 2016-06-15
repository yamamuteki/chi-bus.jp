module ApplicationHelper
  def build_markers(bus_stops, position = nil)
    markers = []
    if position then
      markers += Gmaps4rails.build_markers([position]) do |p, marker|
        marker.lat p.split(',')[0]
        marker.lng p.split(',')[1]
        marker.picture({ url: image_path('bluedot.png'), width: '20', height: '20' })
      end
    end
    markers += Gmaps4rails.build_markers(bus_stops) do |bus_stop, marker|
      marker.lat bus_stop.latitude
      marker.lng bus_stop.longitude
      marker.title bus_stop.name
      marker.infowindow render partial: 'application/infowindow', locals: { bus_stop: bus_stop }
      marker.json({ id: bus_stop.id })
    end
    markers
  end

  def build_routes(bus_routes)
    bus_routes.map do |bus_route|
      {
        id: bus_route.id,
        tracks: bus_route.bus_route_tracks.map do |track|
          track.coordinates.map do |coordinate|
            { lat: coordinate[0], lng: coordinate[1] }
          end.compact
        end
      }
    end
  end

  def gravatar_for(email, size)
    gravatar_id = Digest::MD5::hexdigest(email.downcase)
    gravatar_url = "https://secure.gravatar.com/avatar/#{gravatar_id}?s=#{size}"
    image_tag(gravatar_url, class: 'gravatar')
  end
end
