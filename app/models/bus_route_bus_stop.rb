class BusRouteBusStop < ActiveRecord::Base
  belongs_to :bus_route
  belongs_to :bus_stop
end
