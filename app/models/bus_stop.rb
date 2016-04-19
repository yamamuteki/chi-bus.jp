class BusStop < ActiveRecord::Base
  has_and_belongs_to_many :bus_route_infos
  def address
    Geocoder.address("#{self.latitude},#{self.longitude}")
  end
end
