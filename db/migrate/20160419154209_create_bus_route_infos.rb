class CreateBusRouteInfos < ActiveRecord::Migration
  def change
    create_table :bus_route_infos do |t|
      t.integer :bus_type
      t.string :operation_company
      t.string :line_name

      t.timestamps null: false
    end
  end
end
