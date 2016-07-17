class BusRouteTrack < ApplicationRecord
  belongs_to :bus_route
  serialize :coordinates, JSON
end
