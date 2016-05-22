namespace :keyword do
  desc 'Generate keywords'
  task generate: :environment do
    progress = ProgressBar.create(title: "Generate", total: BusStop.count, format: '%t: %J%% |%B|')
    ActiveRecord::Base.transaction do
      BusStop.find_each.each do |bus_stop|
        keyword = [
          bus_stop.name,
          kakasi_parse(Kakasi.kakasi('-Ja -Ha -Ka -ka -Ea -p', bus_stop.name).delete('^')).join(' '),
          kakasi_parse(Kakasi.kakasi('-JH -aH -KH -kH -EH -p', bus_stop.name)).join(' '),
          kakasi_parse(Kakasi.kakasi('-JK -aK -HK -kK -EK -p', bus_stop.name)).join(' ')
        ].join(' ')
        bus_stop.update(keyword: keyword)
        progress.increment
      end
    end
  end

  def kakasi_parse(kakasi_result)
    kakasi_result.scan(/[^{}]+/).map{ |t| t.split('|') }.reduce{ |a,b| a.product(b) }.map{ |c| c.is_a?(Array) ? c.join : c }
  end

  desc 'Dump keywords'
  task dump: :environment do
    progress = ProgressBar.create(title: "Dump", total: BusStop.count, format: '%t: %J%% |%B|')
    File.write('db/keywords.json', JSON.pretty_generate(
      BusStop.find_each.map do |bus_stop|
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
