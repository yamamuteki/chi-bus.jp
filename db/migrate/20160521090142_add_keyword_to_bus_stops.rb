class AddKeywordToBusStops < ActiveRecord::Migration
  def change
    add_column :bus_stops, :keyword, :string
  end
end
