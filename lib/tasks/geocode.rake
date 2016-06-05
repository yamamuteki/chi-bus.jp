namespace :geocode do
  desc 'Generate geocording data'
  task generate: :environment do
    query = BusStop.where(formatted_address: nil);
    progress = ProgressBar.create(title: "Generate", total: query.count, format: '%t: %J%% |%B|')
    query.find_each.each do |bus_stop|
      bus_stop.reverse_geocode
      bus_stop.save!
      progress.increment
    end
  end

  desc 'Dump geocording data'
  task dump: :environment do
    progress = ProgressBar.create(title: "Dump", total: BusStop.count, format: '%t: %J%% |%B|')
    File.write('db/geocording_data.json', JSON.pretty_generate(
      BusStop.find_each.map do |bus_stop|
        progress.increment
        {
          bus_stop_id: bus_stop.id,
          postal_code: bus_stop.postal_code,
          city: bus_stop.city,
          formatted_address: bus_stop.formatted_address
        }
      end
    ))
  end

  desc 'Restore geocording data'
  task restore: :environment do
    progress = ProgressBar.create(title: "Restore", total: BusStop.count, format: '%t: %J%% |%B|')
    ActiveRecord::Base.transaction do
      JSON.parse(File.read('db/geocording_data.json')).each do |record|
        bus_stop = BusStop.find record['bus_stop_id']
        bus_stop.update(
          postal_code: record['postal_code'],
          city: record['city'],
          formatted_address: record['formatted_address']
        )
        progress.increment
      end
    end
  end
end
