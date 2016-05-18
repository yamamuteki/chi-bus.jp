class BusStop < ActiveRecord::Base
  has_many :bus_route_bus_stops
  has_many :bus_routes, -> { order('operation_company, line_name') }, through: :bus_route_bus_stops
  reverse_geocoded_by :latitude, :longitude, address: :formatted_address do |model, results|
    if geo = results.first
      model.postal_code = geo.postal_code
      # model.prefecture = geo.state # Imported db/seeds.rb
      model.city = geo.address_components_of_type(:locality).last['long_name'] if geo.address_components_of_type(:locality).last
      model.formatted_address = geo.formatted_address.delete('日本, ')
    end
  end

  def address
    formatted_address
  end

  def formatted_address
    self[:formatted_address].to_s
  end
end
