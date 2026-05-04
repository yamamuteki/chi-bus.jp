namespace :data do
  XML_PREFECTURES = [
    [ "12", "千葉県" ],
    [ "13", "東京都" ],
    [ "14", "神奈川県" ],
    [ "11", "埼玉県" ],
    [ "08", "茨城県" ],
    [ "09", "栃木県" ],
    [ "10", "群馬県" ]
  ].freeze

  TABLES = %w[bus_routes bus_route_tracks bus_stops bus_route_bus_stops].freeze

  desc "Generate db/data/*.csv from XML and JSON sources"
  task generate: :environment do
    require "nokogiri"
    require "simplify_rb"
    require "csv"
    require "json"

    data_dir = Rails.root.join("db/data")
    data_dir.mkpath

    now = Time.zone.now

    bus_route_tracks = []
    bus_routes = []
    bus_stops = []
    bus_route_bus_stops = []

    track_id_by_gml = {}
    route_id_by_key = {}

    # XML: BusRouteTrack & BusRoute
    XML_PREFECTURES.each do |code, _prefecture|
      xml_path = "db/N07-11_#{code}.xml"
      doc = Nokogiri::XML(File.open(xml_path))
      doc.remove_namespaces!

      progress = ProgressBar.create(title: "Tracks #{code}", total: doc.css("Curve").count, format: "%t: %J%% |%B|")
      doc.css("Curve").each do |node|
        gml_id = "#{xml_path}/#{node['id']}"
        coordinates = node.at("posList").text.strip.each_line.map { |line| { x: line.split[0].to_f, y: line.split[1].to_f } }
        simplified = SimplifyRb::Simplifier.new.process(coordinates, 0.0001).map { |c| [ c[:x], c[:y] ] }

        # Use Float#to_s (via interpolation) for the shortest round-trip
        # representation; the json gem's Float#to_json renders 17 digits.
        coordinates_json = "[" + simplified.map { |x, y| "[#{x},#{y}]" }.join(",") + "]"

        track_id = bus_route_tracks.size + 1
        bus_route_tracks << {
          id: track_id,
          gml_id: gml_id,
          coordinates: coordinates_json,
          bus_route_id: nil,
          created_at: now,
          updated_at: now
        }
        track_id_by_gml[gml_id] = track_id
        progress.increment
      end

      progress = ProgressBar.create(title: "Routes #{code}", total: doc.css("BusRoute").count, format: "%t: %J%% |%B|")
      doc.css("BusRoute").each do |node|
        href = node.at("brt")["href"].remove "#"
        bus_type = node.at("bsc").text.to_i
        operation_company = node.at("boc").text
        line_name = node.at("bln").text
        weekday_rate = node.at("rpd").text.to_f
        saturday_rate = node.at("rps").text.to_f
        holiday_rate = node.at("rph").text.to_f
        note = node.at("rmk").text

        key = [ bus_type, operation_company, line_name, weekday_rate, saturday_rate, holiday_rate, note ]
        route_id = route_id_by_key[key]
        unless route_id
          route_id = bus_routes.size + 1
          bus_routes << {
            id: route_id,
            bus_type: bus_type,
            operation_company: operation_company,
            line_name: line_name,
            weekday_rate: weekday_rate,
            saturday_rate: saturday_rate,
            holiday_rate: holiday_rate,
            note: note,
            created_at: now,
            updated_at: now
          }
          route_id_by_key[key] = route_id
        end

        track_gml = "#{xml_path}/#{href}"
        if (track_id = track_id_by_gml[track_gml])
          bus_route_tracks[track_id - 1][:bus_route_id] = route_id
        end
        progress.increment
      end
    end

    # XML: BusStop & BusRouteBusStop
    route_lookup = {}
    bus_routes.each do |r|
      route_lookup[[ r[:bus_type], r[:operation_company], r[:line_name] ]] ||= r[:id]
    end

    XML_PREFECTURES.each do |code, prefecture|
      xml_path = "db/P11-10_#{code}-jgd-g.xml"
      doc = Nokogiri::XML(File.open(xml_path))
      doc.remove_namespaces!

      pos_hash = {}
      doc.css("Point").each { |n| pos_hash[n["id"]] = n.at("pos").text }

      progress = ProgressBar.create(title: "Stops #{code}", total: doc.css("BusStop").count, format: "%t: %J%% |%B|")
      doc.css("BusStop").each do |node|
        gml_id = node["id"]
        name = node.at("busStopName").text
        href = node.at("position")["href"].remove "#"
        pos = pos_hash[href]

        bs_id = bus_stops.size + 1
        bus_stops << {
          id: bs_id,
          gml_id: gml_id,
          name: name,
          latitude: pos.split[0].to_f,
          longitude: pos.split[1].to_f,
          created_at: now,
          updated_at: now,
          postal_code: nil,
          prefecture: prefecture,
          city: nil,
          formatted_address: nil,
          keyword: nil
        }

        node.css("BusRouteInformation").each do |info_node|
          bt = info_node.at("busType").text.to_i
          oc = info_node.at("busOperationCompany").text
          ln = info_node.at("busLineName").text
          if (route_id = route_lookup[[ bt, oc, ln ]])
            bus_route_bus_stops << {
              id: bus_route_bus_stops.size + 1,
              bus_route_id: route_id,
              bus_stop_id: bs_id,
              bus_stop_number: nil,
              created_at: now,
              updated_at: now
            }
          end
        end
        progress.increment
      end
    end

    # JSON merge
    JSON.parse(File.read("db/bus_stop_number.json")).each do |rec|
      idx = rec["bus_route_bus_stop_id"] - 1
      bus_route_bus_stops[idx][:bus_stop_number] = rec["bus_stop_number"] if bus_route_bus_stops[idx]
    end

    JSON.parse(File.read("db/geocording_data.json")).each do |rec|
      idx = rec["bus_stop_id"] - 1
      next unless bus_stops[idx]
      bus_stops[idx][:postal_code] = rec["postal_code"]
      bus_stops[idx][:city] = rec["city"]
      bus_stops[idx][:formatted_address] = rec["formatted_address"]
    end

    JSON.parse(File.read("db/keywords.json")).each do |rec|
      idx = rec["bus_stop_id"] - 1
      bus_stops[idx][:keyword] = rec["keyword"] if bus_stops[idx]
    end

    # CSV write (PostgreSQL COPY ... CSV HEADER 互換)
    write_csv = ->(name, rows, columns) do
      path = data_dir.join("#{name}.csv")
      CSV.open(path, "w", headers: columns, write_headers: true) do |csv|
        rows.each { |row| csv << columns.map { |c| row[c.to_sym] } }
      end
      puts "Wrote #{path} (#{rows.size} rows)"
    end

    write_csv.call("bus_routes", bus_routes,
                   %w[id bus_type operation_company line_name weekday_rate saturday_rate holiday_rate note created_at updated_at])
    write_csv.call("bus_route_tracks", bus_route_tracks,
                   %w[id gml_id coordinates bus_route_id created_at updated_at])
    write_csv.call("bus_stops", bus_stops,
                   %w[id gml_id name latitude longitude created_at updated_at postal_code prefecture city formatted_address keyword])
    write_csv.call("bus_route_bus_stops", bus_route_bus_stops,
                   %w[id bus_route_id bus_stop_id bus_stop_number created_at updated_at])
  end

  desc "Load db/data/*.csv into the database (TRUNCATE + COPY FROM STDIN)"
  task load: :environment do
    raw = ActiveRecord::Base.connection.raw_connection

    ActiveRecord::Base.transaction do
      raw.exec("TRUNCATE TABLE #{TABLES.join(', ')} RESTART IDENTITY CASCADE")

      TABLES.each do |table|
        path = Rails.root.join("db/data/#{table}.csv")
        raise "Missing #{path}. Run 'rails data:generate' first." unless path.exist?

        # CSV のヘッダ行を読み、列順を COPY 文に明示する。
        # COPY ... CSV HEADER はヘッダを読み飛ばすだけで列マッピングをしないため、
        # CSV と DB の物理カラム順が異なる環境（schema:load 由来など）で壊れる。
        columns = File.open(path, "r") { |f| f.readline.chomp.split(",") }

        raw.copy_data("COPY #{table} (#{columns.join(', ')}) FROM STDIN WITH CSV HEADER") do
          File.open(path, "r") do |f|
            while (line = f.gets)
              raw.put_copy_data(line)
            end
          end
        end
        # Reset sequence to MAX(id) so subsequent inserts work
        raw.exec("SELECT setval(pg_get_serial_sequence('#{table}', 'id'), COALESCE(MAX(id), 0) + 1, false) FROM #{table}")
        puts "Loaded #{path}"
      end
    end
  end
end
