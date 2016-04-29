class DropBusRouteInfos < ActiveRecord::Migration
  def change
    drop_table :bus_route_infos
  end
end
