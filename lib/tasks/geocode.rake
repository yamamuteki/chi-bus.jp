# 国土交通省 位置参照情報 (ISJ, 大字・町丁目レベル) を使ったオフライン reverse
# geocoding。bus_stops の (latitude, longitude) → (city, formatted_address) を populate する。
#
# data:generate と同じ「CSV を git で管理する」方針: generate は DB を更新せず
# db/data/geocoding.csv に書き出す。load は CSV から bulk UPDATE する。
#
# 取り込み元: db/isj/{prefcode}-18.0b/*.csv (47 都道府県分、計約 19 万 entries)。
# 詳細: https://nlftp.mlit.go.jp/cgi-bin/isj/dls/_choose_method.cgi
# raw zip は db/isj/ に展開。.gitignore で除外。
#
# bus_stops.prefecture は P11 XML 由来で既に埋まっているため上書きしない。
# city と formatted_address のみ ISJ から populate する。
namespace :geocode do
  CSV_PATH = "db/data/geocoding.csv.gz".freeze
  ISJ_DIR = "db/isj".freeze

  desc "Generate geocoding into db/data/geocoding.csv.gz (does not touch DB)"
  task generate: :environment do
    require "csv"
    require "zlib"
    $stdout.sync = true

    unless Dir.exist?(ISJ_DIR) && !Dir.empty?(ISJ_DIR)
      raise "Missing #{ISJ_DIR}. Download ISJ data from " \
            "https://nlftp.mlit.go.jp/cgi-bin/isj/dls/_choose_method.cgi and unzip into #{ISJ_DIR}"
    end

    puts "Loading ISJ entries from #{ISJ_DIR}..."
    geocoder = IsjReverseGeocoder.from_directory(ISJ_DIR)
    entry_count = geocoder.instance_variable_get(:@entries).size
    puts "  loaded #{entry_count} entries"

    rows = []
    miss = 0
    ActiveRecord::Base.logger.silence(Logger::WARN) do
      BusStop.find_each do |bs|
        entry = geocoder.reverse_geocode(bs.latitude, bs.longitude)
        if entry
          rows << [ bs.id, entry.city, IsjReverseGeocoder.format_address(entry) ]
        else
          miss += 1
        end
      end
    end

    rows.sort_by! { |r| r[0] }
    Zlib::GzipWriter.open(CSV_PATH) do |gz|
      csv = CSV.new(gz, headers: %w[bus_stop_id city formatted_address], write_headers: true)
      rows.each { |row| csv << row }
    end
    puts "Wrote #{CSV_PATH} (#{rows.size} rows, #{miss} bus_stops without match)"
  end

  desc "Load geocoding from db/data/geocoding.csv.gz into bus_stops.city / formatted_address"
  task load: :environment do
    require "zlib"
    raise "Missing #{CSV_PATH}. Run 'rails geocode:generate' first." unless File.exist?(CSV_PATH)

    raw = ActiveRecord::Base.connection.raw_connection
    ActiveRecord::Base.transaction do
      raw.exec(<<~SQL)
        CREATE TEMP TABLE _tmp_geocoding (
          bus_stop_id INTEGER,
          city TEXT,
          formatted_address TEXT
        ) ON COMMIT DROP
      SQL

      raw.copy_data("COPY _tmp_geocoding (bus_stop_id, city, formatted_address) FROM STDIN WITH CSV HEADER") do
        Zlib::GzipReader.open(CSV_PATH) do |f|
          while (line = f.gets)
            raw.put_copy_data(line)
          end
        end
      end

      # 1 SQL で bulk UPDATE。prefecture (XML 由来) は触らない。
      raw.exec(<<~SQL)
        UPDATE bus_stops AS bs
        SET city = t.city,
            formatted_address = t.formatted_address
        FROM _tmp_geocoding AS t
        WHERE bs.id = t.bus_stop_id
      SQL
    end
    puts "Loaded #{CSV_PATH}"
  end
end
