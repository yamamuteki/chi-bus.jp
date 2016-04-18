# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

require 'nokogiri'

doc = Nokogiri::XML(open("db/P11-10_12-jgd-g.xml"))
doc.remove_namespaces!

ActiveRecord::Base.transaction do
  BusStop.delete_all

  pos_hash = {}
  doc.css('Point').each do |node|
    pos_hash[node['id']] = node.at('pos').text
  end

  count = doc.css('BusStop').count
  doc.css('BusStop').each_with_index do |node, index|
    gml_id = node['id']
    name = node.at('busStopName').text
    href = node.at('position')['href'].remove '#'
    pos = pos_hash[href]
    bus_stop = BusStop.create(gml_id: gml_id, name: name, latitude: pos.split[0], longitude: pos.split[1])
    print "\rBusStop:#{'%5.1f' % (index * 100.0 / count) }%"
  end
  puts
end
