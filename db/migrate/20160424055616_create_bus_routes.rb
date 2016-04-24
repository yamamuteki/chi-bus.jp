class CreateBusRoutes < ActiveRecord::Migration
  def change
    create_table :bus_routes do |t|
      t.integer :bus_type
      t.string :operation_company
      t.string :line_name
      t.float :weekday_rate
      t.float :saturday_rate
      t.float :holiday_rate
      t.string :note
      t.references :bus_route_info, index: true

      t.timestamps null: false
    end
  end
end
