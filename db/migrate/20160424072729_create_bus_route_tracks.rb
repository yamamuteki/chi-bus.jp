class CreateBusRouteTracks < ActiveRecord::Migration
  def change
    create_table :bus_route_tracks do |t|
      t.string :gml_id
      t.text :coordinates
      t.references :bus_route, index: true, foreign_key: true

      t.timestamps null: false

      t.index :gml_id
    end
  end
end
