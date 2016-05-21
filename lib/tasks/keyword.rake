namespace :keyword do
  desc 'Generate keywords'
  task generate: :environment do
    progress = ProgressBar.create(title: "Generate", total: BusStop.count, format: '%t: %J%% |%B|')
    ActiveRecord::Base.transaction do
      BusStop.all.each do |bus_stop|
        keyword = [
          bus_stop.name,
          Kakasi.kakasi('-Ja -Ha -Ka -ka -Ea', bus_stop.name).delete('^'),
          Kakasi.kakasi('-JH -aH -KH -kH -EH', bus_stop.name),
          Kakasi.kakasi('-JK -aK -HK -kK -EK', bus_stop.name)
        ].join(' ')
        bus_stop.update(keyword: keyword)
        progress.increment
      end
    end
  end

  desc 'Dump keywords'
  task dump: :environment do
    progress = ProgressBar.create(title: "Dump", total: BusStop.count, format: '%t: %J%% |%B|')
    File.write('db/keywords.json', JSON.pretty_generate(
      BusStop.all.map do |bus_stop|
        progress.increment
        {
          bus_stop_id: bus_stop.id,
          keyword: bus_stop.keyword
        }
      end
    ))
  end

  desc 'Restore keywords'
  task restore: :environment do
    progress = ProgressBar.create(title: "Restore", total: BusStop.count, format: '%t: %J%% |%B|')
    ActiveRecord::Base.transaction do
      JSON.parse(File.read('db/keywords.json')).each do |record|
        bus_stop = BusStop.find record['bus_stop_id']
        bus_stop.update(
          keyword: record['keyword']
        )
        progress.increment
      end
    end
  end
end
