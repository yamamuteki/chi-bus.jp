namespace :geocode do
  desc 'Dump geocording data'
  task dump: :environment do
    File.write('db/geocording_data.json', JSON.pretty_generate(
      BusStop.all.map do |record|
        [
          record.id,
          {
            postal_code: record.postal_code,
            city: record.city,
            formatted_address: record.formatted_address
          }
        ]
      end.to_h
    ))
  end

  desc 'Restore geocording data'
  task restore: :environment do
    progress = ProgressBar.create(title: "Restore", total: BusStop.count, format: '%t: %J%% |%B|')
    hash = JSON.parse(File.read('db/geocording_data.json'))
    ActiveRecord::Base.transaction do
      BusStop.find_each do |record|
        current_hash = hash[record.id.to_s]
        record.update(
          postal_code: current_hash['postal_code'],
          city: current_hash['city'],
          formatted_address: current_hash['formatted_address']
        )
        progress.increment
      end
    end
  end
end
