class BusStop < ActiveRecord::Base
  has_and_belongs_to_many :bus_route_infos, -> { order('operation_company, line_name') }
  reverse_geocoded_by :latitude, :longitude
  def address
    Geocoder.address("#{self.latitude},#{self.longitude}")
  end
end
