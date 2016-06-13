class BusStop < ActiveRecord::Base
  has_many :bus_route_bus_stops
  has_many :bus_routes, -> { order('operation_company, line_name') }, through: :bus_route_bus_stops
  reverse_geocoded_by :latitude, :longitude, address: :formatted_address do |model, results|
    geo = results.first
    if geo
      model.postal_code = geo.postal_code
      # model.prefecture = geo.state # Imported db/seeds.rb
      city_node = geo.address_components.find { |c| c['types'] == ['locality', 'political'] }
      model.city = city_node['long_name'] if city_node
      model.formatted_address = geo.formatted_address.sub('日本, ', '')
    end
  end

  def address
    formatted_address
  end

  def formatted_address
    self[:formatted_address].to_s
  end
end
