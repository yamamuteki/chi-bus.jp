class BusStopsController < ApplicationController
  def index
    if params[:q] then
      @bus_stops = BusStop.preload(:bus_routes).where("keyword like '%#{params[:q]}%'").order('name, latitude DESC').limit(100)
      if @bus_stops.empty?
        client = GooglePlaces::Client.new(Rails.application.secrets.google_api_key)
        spots = Rails.cache.fetch(params[:q]) do
          # The maximum allowed radius is 50,000 meters in Google Places API Web Service
          # 千葉県庁@35.6049233,140.1208483
          client.spots_by_query(params[:q], lat: 35.6049233, lng: 140.1208483, radius: 50_000, language: 'ja')
        end
        @bus_stops = spots.map { |spot| Place.new(spot) }
      end
    elsif params[:position]
      latitude = params[:position].split(',')[0].to_f
      longitude = params[:position].split(',')[1].to_f
      @bus_stops = BusStop.preload(:bus_routes).near([latitude, longitude], 20000).limit(12)
    else
      @bus_stops = []
    end
  end

  def show
    @bus_stop = BusStop.preload(bus_routes: [:bus_stops, :bus_route_tracks]).find(params[:id])
  end
end
