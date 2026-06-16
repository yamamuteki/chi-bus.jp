# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_16_110227) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "bus_route_bus_stops", id: :serial, force: :cascade do |t|
    t.integer "bus_route_id"
    t.integer "bus_stop_id"
    t.integer "bus_stop_number"
    t.index ["bus_route_id"], name: "index_bus_route_bus_stops_on_bus_route_id"
    t.index ["bus_stop_id"], name: "index_bus_route_bus_stops_on_bus_stop_id"
  end

  create_table "bus_route_tracks", id: :serial, force: :cascade do |t|
    t.integer "bus_route_id"
    t.text "coordinates"
    t.string "gml_id"
    t.index ["bus_route_id"], name: "index_bus_route_tracks_on_bus_route_id"
    t.index ["gml_id"], name: "index_bus_route_tracks_on_gml_id"
  end

  create_table "bus_routes", id: :serial, force: :cascade do |t|
    t.integer "bus_type"
    t.boolean "fragmented", default: false, null: false
    t.float "holiday_rate"
    t.string "line_name"
    t.string "note"
    t.string "operation_company"
    t.float "saturday_rate"
    t.float "weekday_rate"
  end

  create_table "bus_stops", id: :serial, force: :cascade do |t|
    t.string "city"
    t.string "formatted_address"
    t.string "gml_id"
    t.text "keyword"
    t.float "latitude"
    t.float "longitude"
    t.string "name"
    t.string "prefecture"
    t.index ["keyword"], name: "index_bus_stops_on_keyword", opclass: :gin_trgm_ops, using: :gin
    t.index ["name"], name: "index_bus_stops_on_name", opclass: :gin_trgm_ops, using: :gin
  end

  add_foreign_key "bus_route_bus_stops", "bus_routes"
  add_foreign_key "bus_route_bus_stops", "bus_stops"
  add_foreign_key "bus_route_tracks", "bus_routes"
end
