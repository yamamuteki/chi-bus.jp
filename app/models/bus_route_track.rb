class BusRouteTrack < ActiveRecord::Base
  belongs_to :bus_route
  serialize :coordinates, JSON
end
