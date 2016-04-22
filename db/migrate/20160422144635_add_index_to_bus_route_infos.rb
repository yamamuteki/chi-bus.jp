class AddIndexToBusRouteInfos < ActiveRecord::Migration
  def change
    add_index :bus_route_infos, [:bus_type, :operation_company, :line_name], name: 'index_bus_route_infos_on_bus_type_operation_company_line_name'
  end
end
