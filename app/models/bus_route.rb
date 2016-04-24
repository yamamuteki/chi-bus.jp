class BusRoute < ActiveRecord::Base
  belongs_to :bus_route_info
  has_many :bus_route_tracks
end
