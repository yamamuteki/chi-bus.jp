class RemoveBusRouteInfoIdFromBusRoutes < ActiveRecord::Migration
  def change
    remove_column :bus_routes, :bus_route_info_id
  end
end
