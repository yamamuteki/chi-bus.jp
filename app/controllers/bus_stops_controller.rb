class BusStopsController < ApplicationController
  def index
    if params[:q] then
      # `keyword` と `name` の両方に GIN trigram インデックス (pg_trgm) を張っている。
      # `lower()` で wrap すると planner が index を使えなくなるため ILIKE で書く。
      # OR にしているのは keyword:load 未実行 / kakasi 失敗で keyword が NULL の停留所も
      # name 側で hit させて Google Places フォールバックに流れないようにする保険。
      # 3 文字以上の検索なら BitmapOr で両 index を結合して ~0.3ms。
      pattern = "%#{params[:q]}%"
      @bus_stops = BusStop.preload(:bus_routes)
                          .where("keyword ILIKE :p OR name ILIKE :p", p: pattern)
                          .order("name, latitude DESC").limit(100)
      if @bus_stops.empty?
        client = GooglePlaces::Client.new(ENV["GOOGLE_API_KEY"])
        spots = Rails.cache.fetch(params[:q]) do
          # The maximum allowed radius is 50,000 meters in Google Places API Web Service
          # 千葉県庁@35.6049233,140.1208483
          client.spots_by_query(params[:q], lat: 35.6049233, lng: 140.1208483, radius: 50_000, language: "ja")
        end
        @bus_stops = spots.map { |spot| Place.new(spot) }
      end
    elsif params[:position]
      latitude = params[:position].split(",")[0].to_f
      longitude = params[:position].split(",")[1].to_f
      @bus_stops = BusStop.preload(:bus_routes).near([ latitude, longitude ], 20000).limit(12)
    else
      @bus_stops = []
    end
  end

  def show
    @bus_stop = BusStop.preload(bus_routes: [ :bus_stops, :bus_route_tracks ]).find(params[:id])
  end
end
