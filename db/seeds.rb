# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

require 'nokogiri'

def load_bus_stops
  BusStop.delete_all
  BusRouteInfo.delete_all

  doc = Nokogiri::XML(open('db/P11-10_12-jgd-g.xml'))
  doc.remove_namespaces!

  pos_hash = {}
  doc.css('Point').each do |node|
    pos_hash[node['id']] = node.at('pos').text
  end

  bus_stop_progress = ProgressBar.create(title: "BusStop", total: doc.css('BusStop').count, format: '%t: %J%% |%B|')
  doc.css('BusStop').each do |node|
    gml_id = node['id']
    name = node.at('busStopName').text
    href = node.at('position')['href'].remove '#'
    pos = pos_hash[href]
    bus_stop = BusStop.create(gml_id: gml_id, name: name, latitude: pos.split[0], longitude: pos.split[1])
    node.css('BusRouteInformation').each do |info_node|
      bus_type = info_node.at('busType').text.to_i
      operation_company = info_node.at('busOperationCompany').text
      line_name = info_node.at('busLineName').text
      info = BusRouteInfo.find_or_create_by(bus_type: bus_type, operation_company: operation_company, line_name: line_name)
      bus_stop.bus_route_infos << info
    end
    bus_stop_progress.increment
  end
end

def load_bus_routes
  BusRouteTrack.delete_all
  BusRoute.delete_all

  doc = Nokogiri::XML(open('db/N07-11_12.xml'))
  doc.remove_namespaces!

  bus_route_track_progress = ProgressBar.create(title: "BusRouteTrack", total: doc.css('Curve').count, format: '%t: %J%% |%B|')
  doc.css('Curve').each do |node|
    gml_id = node['id']
    coordinates = node.at('posList').text.strip.each_line.map { |line| line.split.map(&:to_f) }
    bus_route_track = BusRouteTrack.create(gml_id: gml_id, coordinates: coordinates)
    bus_route_track_progress.increment
  end

  bus_route_progress = ProgressBar.create(title: "BusRoute", total: doc.css('BusRoute').count, format: '%t: %J%% |%B|')
  doc.css('BusRoute').each do |node|
    href = node.at('brt')['href'].remove '#'
    bus_type = node.at('bsc').text.to_i
    operation_company = node.at('boc').text
    line_name = node.at('bln').text
    weekday_rate = node.at('rpd').text.to_f
    saturday_rate = node.at('rps').text.to_f
    holiday_rate = node.at('rph').text.to_f
    note = node.at('rmk').text
    bus_route = BusRoute.find_or_create_by(
      bus_type: bus_type,
      operation_company: operation_company,
      line_name: line_name,
      weekday_rate: weekday_rate,
      saturday_rate: saturday_rate,
      holiday_rate: holiday_rate,
      note: note
    )
    bus_route.bus_route_tracks << BusRouteTrack.find_by(gml_id: href)
    bus_route_info = BusRouteInfo.find_by(bus_type: bus_type, operation_company: operation_company, line_name: line_name)
    bus_route_info.bus_route = bus_route if bus_route_info
    bus_route_progress.increment
  end
end

ActiveRecord::Base.transaction do
  load_bus_stops
  load_bus_routes
end
