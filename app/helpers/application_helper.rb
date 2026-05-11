module ApplicationHelper
  def build_markers(bus_stops, position = nil)
    markers = []
    if position then
      markers += Gmaps4rails.build_markers([ position ]) do |p, marker|
        marker.lat p.split(",")[0]
        marker.lng p.split(",")[1]
        marker.picture({ url: image_path("bluedot.png"), width: "20", height: "20" })
      end
    end
    markers += Gmaps4rails.build_markers(bus_stops) do |bus_stop, marker|
      marker.lat bus_stop.latitude
      marker.lng bus_stop.longitude
      badge = bus_stop_badge(bus_stop)
      # title はホバー時の即時 tooltip 文言。「渋谷駅（10）」のように停留所名 + 通過路線数 (Place は「周辺」)。
      marker.title "#{bus_stop.name}（#{badge}）"
      # 通過路線が 1 本だけの bus_stop は default の赤マーカーと同じ Google CDN 画像を
      # 指すが、`?style=single` query で <img src> を distinct 化し、CSS 側で
      # `img[src*="?style=single"]` を hue-rotate して水色化する。形状は default と
      # 完全一致するので「色だけ違う」UX を実現できる。Place や 2 路線以上の bus_stop は
      # marker.picture を設定しないため Google Maps の default 赤マーカーが使われる。
      if badge == 1
        # HDPI 版 (52x74) を渡し、display は default と同じ 26x37 にするため
        # application.js 側で setIcon({scaledSize: 26x37}) を後がけする。
        # gmaps4rails の marker.picture API は scaledSize を露出していないため。
        marker.picture({
          url: "https://maps.gstatic.com/mapfiles/api-3/images/spotlight-poi3_hdpi.png?style=single",
          width: "26",
          height: "37"
        })
      end
      # path はマーカークリック時のジャンプ先。BusStop なら詳細ページ、Google Places の
      # Place なら同座標の周辺検索 (= /bus_stops?position=lat,lng) になる。
      marker.json({ id: bus_stop.id, path: bus_stop_or_place_path(bus_stop) })
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
    gravatar_id = Digest::MD5.hexdigest(email.downcase)
    gravatar_url = "https://secure.gravatar.com/avatar/#{gravatar_id}?s=#{size}"
    image_tag(gravatar_url, class: "gravatar")
  end
end
