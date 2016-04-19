class CreateJoinTableBusRouteInfosBusStops < ActiveRecord::Migration
  def change
    create_join_table :bus_route_infos, :bus_stops do |t|
      # t.index [:bus_route_info_id, :bus_stop_id]
      # t.index [:bus_stop_id, :bus_route_info_id]
    end
  end
end
