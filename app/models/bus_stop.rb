class BusStop < ActiveRecord::Base
  def address
    Geocoder.address("#{self.latitude},#{self.longitude}")
  end
end
