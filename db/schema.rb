# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20160424055616) do

  create_table "bus_route_infos", force: :cascade do |t|
    t.integer  "bus_type"
    t.string   "operation_company"
    t.string   "line_name"
    t.datetime "created_at",        null: false
    t.datetime "updated_at",        null: false
  end

  add_index "bus_route_infos", ["bus_type", "operation_company", "line_name"], name: "index_bus_route_infos_on_bus_type_operation_company_line_name"

  create_table "bus_route_infos_stops", id: false, force: :cascade do |t|
    t.integer "bus_route_info_id", null: false
    t.integer "bus_stop_id",       null: false
  end

  add_index "bus_route_infos_stops", ["bus_route_info_id", "bus_stop_id"], name: "index_bus_route_infos_stops_on_bus_route_info_id_bus_stop_id"
  add_index "bus_route_infos_stops", ["bus_stop_id", "bus_route_info_id"], name: "index_bus_route_infos_stops_on_bus_stop_id_bus_route_info_id"

  create_table "bus_routes", force: :cascade do |t|
    t.integer  "bus_type"
    t.string   "operation_company"
    t.string   "line_name"
    t.float    "weekday_rate"
    t.float    "saturday_rate"
    t.float    "holiday_rate"
    t.string   "note"
    t.integer  "bus_route_info_id"
    t.datetime "created_at",        null: false
    t.datetime "updated_at",        null: false
  end

  add_index "bus_routes", ["bus_route_info_id"], name: "index_bus_routes_on_bus_route_info_id"

  create_table "bus_stops", force: :cascade do |t|
    t.string   "gml_id"
    t.string   "name"
    t.float    "latitude"
    t.float    "longitude"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

end
