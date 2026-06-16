class RemoveTimestampsFromStaticTables < ActiveRecord::Migration[8.1]
  def change
    remove_timestamps :bus_routes
    remove_timestamps :bus_route_tracks
    remove_timestamps :bus_stops
    remove_timestamps :bus_route_bus_stops
  end
end
