class BusStop < ActiveRecord::Base
  has_many :bus_route_bus_stops
  has_many :bus_routes, -> { order('operation_company, line_name') }, through: :bus_route_bus_stops
  reverse_geocoded_by :latitude, :longitude
  def address
    # お試し実装。
    Rails.cache.fetch("bus_stop_addresses/#{self.id}") do
      Geocoder.address("#{self.latitude},#{self.longitude}").to_s
    end
  end
  def formatted_address
    # DBにキャッシュしたら返す。
    ''
  end
end
