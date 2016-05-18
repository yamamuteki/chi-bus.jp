class AddColumnsToBusStops < ActiveRecord::Migration
  def change
    add_column :bus_stops, :postal_code, :string
    add_column :bus_stops, :prefecture, :string
    add_column :bus_stops, :city, :string
    add_column :bus_stops, :formatted_address, :string
  end
end
