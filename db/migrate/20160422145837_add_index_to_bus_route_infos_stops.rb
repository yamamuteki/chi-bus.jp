class AddIndexToBusRouteInfosStops < ActiveRecord::Migration
  def change
      add_index :bus_route_infos_stops, [:bus_route_info_id, :bus_stop_id], name: 'index_bus_route_infos_stops_on_bus_route_info_id_bus_stop_id'
      add_index :bus_route_infos_stops, [:bus_stop_id, :bus_route_info_id], name: 'index_bus_route_infos_stops_on_bus_stop_id_bus_route_info_id'
  end
end
