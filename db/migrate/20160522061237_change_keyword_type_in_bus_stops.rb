class ChangeKeywordTypeInBusStops < ActiveRecord::Migration
  def up
    change_column :bus_stops, :keyword, :text
  end

  def down
    change_column :bus_stops, :keyword, :string
  end
end
