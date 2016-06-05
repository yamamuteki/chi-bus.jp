namespace :bus_stop_number do
  desc 'Generate bus stop number'
  task generate: :environment do
    progress = ProgressBar.create(title: "Generate", total: BusRoute.count, format: '%t: %J%% |%B|')
    ActiveRecord::Base.transaction do
      BusRouteBusStop.update_all(bus_stop_number: nil)
      BusRoute.find_each do |bus_route|
        index = 0
        bus_route_bus_stops = bus_route.bus_route_bus_stops
        bus_route.bus_route_tracks.sort_by{ |t| t.coordinates[0][1] }.each do |track|
          track.coordinates.each do |coordinate|
            latitude = coordinate[0]
            longitude = coordinate[1]
            bus_route_bus_stops.each do |bus_route_bus_stop|
              next if bus_route_bus_stop.bus_stop_number
              bus_stop = bus_route_bus_stop.bus_stop
              distance = (bus_stop.latitude - latitude) ** 2 + (bus_stop.longitude - longitude) ** 2
              if distance < 0.000001 then
                bus_route_bus_stop.bus_stop_number = index += 1
                bus_route_bus_stop.save
                break
              end
            end
          end
        end
        progress.increment
      end
    end
  end

  desc 'Dump bus stop number'
  task dump: :environment do
    progress = ProgressBar.create(title: "Dump", total: BusRouteBusStop.count, format: '%t: %J%% |%B|')
    File.write('db/bus_stop_number.json', JSON.pretty_generate(
      BusRouteBusStop.find_each.map do |bus_route_bus_stop|
        progress.increment
        {
          bus_route_bus_stop_id: bus_route_bus_stop.id,
          bus_stop_number: bus_route_bus_stop.bus_stop_number
        }
      end
    ))
  end

  desc 'Restore bus stop number'
  task restore: :environment do
    records = JSON.parse(File.read('db/bus_stop_number.json'))
    progress = ProgressBar.create(title: "Restore", total: records.count, format: '%t: %J%% |%B|')
    ActiveRecord::Base.transaction do
      records.each do |record|
        bus_route_bus_stop = BusRouteBusStop.find record['bus_route_bus_stop_id']
        bus_route_bus_stop.update(
          bus_stop_number: record['bus_stop_number']
        )
        progress.increment
      end
    end
  end
end
