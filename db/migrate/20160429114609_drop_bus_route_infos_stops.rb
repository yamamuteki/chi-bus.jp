class DropBusRouteInfosStops < ActiveRecord::Migration
  def change
    drop_table :bus_route_infos_stops
  end
end
