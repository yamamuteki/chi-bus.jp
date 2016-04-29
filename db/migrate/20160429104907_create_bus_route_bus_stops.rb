class CreateBusRouteBusStops < ActiveRecord::Migration
  def change
    create_table :bus_route_bus_stops do |t|
      t.references :bus_route, index: true, foreign_key: true
      t.references :bus_stop, index: true, foreign_key: true
      t.integer :bus_stop_number

      t.timestamps null: false
    end
  end
end
