class AddFragmentedToBusRoutes < ActiveRecord::Migration[8.1]
  def change
    add_column :bus_routes, :fragmented, :boolean, default: false, null: false
  end
end
