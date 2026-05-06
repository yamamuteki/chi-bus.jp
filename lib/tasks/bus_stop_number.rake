# 路線内のバス停の「順番」(BusRouteBusStop#bus_stop_number) を計算・永続化する rake タスク群。
#
# data.rake と同じ「CSV を git で管理する」方針を踏襲し、generate は DB を一切更新せず
# 直接 CSV に書き出す。load 時に CSV を読んで DB の bus_route_bus_stops.bus_stop_number 列を
# UPDATE する（temp table 経由で 1 SQL の bulk update）。
#
# generate: DB から計算 → db/data/bus_stop_numbers.csv（DB は変更しない）
# load:     db/data/bus_stop_numbers.csv → DB に bulk UPDATE
#
# 通常のセットアップでは generate は呼ばず、load のみで CSV を反映する。
# generate は再生成すると順序が変わりうる（CLAUDE.md 参照）。
namespace :bus_stop_number do
  desc "Generate bus_stop_number into db/data/bus_stop_numbers.csv (does not touch DB)"
  task generate: :environment do
    require "csv"
    csv_path = "db/data/bus_stop_numbers.csv"

    # 1. 路線の bus_route_tracks を TrackStitcher で 1 本の座標列に繋ぎ合わせる。
    # 2. BusStopNumberer で各 brbs に bus_stop_number を割り当てる。
    rows = []
    progress = ProgressBar.create(title: "Generate", total: BusRoute.count, format: "%t: %J%% |%B|")

    BusRoute.find_each do |bus_route|
      bus_route_bus_stops = bus_route.bus_route_bus_stops.reorder(:id).includes(:bus_stop).to_a
      flat_coords = TrackStitcher.call(bus_route.bus_route_tracks.to_a)
      assignments = BusStopNumberer.call(flat_coords: flat_coords, bus_route_bus_stops: bus_route_bus_stops)
      rows.concat(assignments)
      progress.increment
    end

    # bus_route_bus_stop_id 順にソートして CSV に書き出す（diff 比較を安定させるため）。
    rows.sort_by! { |id, _| id }
    CSV.open(csv_path, "w", headers: %w[bus_route_bus_stop_id bus_stop_number], write_headers: true) do |csv|
      rows.each { |row| csv << row }
    end
    puts "Wrote #{csv_path} (#{rows.size} rows)"
  end

  desc "Diagnose TrackStitcher quality per route into tmp/bus_stop_number_diagnostics.csv"
  task diagnose: :environment do
    require "csv"
    out_path = "tmp/bus_stop_number_diagnostics.csv"
    rows = []
    progress = ProgressBar.create(title: "Diagnose", total: BusRoute.count, format: "%t: %J%% |%B|")

    BusRoute.includes(:bus_route_tracks, bus_route_bus_stops: :bus_stop).find_each do |bus_route|
      result = TrackStitcher.call_with_diagnostics(bus_route.bus_route_tracks.to_a)

      # 採番品質の直接指標: bus_stop_number 順に並んだ連続 3 バス停で、AB と BC ベクトルの内積が
      # 負 (= 進行方向が反転している) の数をカウント。順序が物理的に逆走するほど多くなる。
      ordered = bus_route.bus_route_bus_stops
                          .select { |b| b.bus_stop_number }
                          .sort_by(&:bus_stop_number)
      backward_turns = 0
      ordered.each_cons(3) do |a, b, c|
        ab_lat = b.bus_stop.latitude - a.bus_stop.latitude
        ab_lng = b.bus_stop.longitude - a.bus_stop.longitude
        bc_lat = c.bus_stop.latitude - b.bus_stop.latitude
        bc_lng = c.bus_stop.longitude - b.bus_stop.longitude
        dot = ab_lat * bc_lat + ab_lng * bc_lng
        backward_turns += 1 if dot < 0
      end

      rows << [
        bus_route.id,
        "#{bus_route.operation_company} #{bus_route.line_name}".strip,
        result.total_tracks,
        result.skipped_parallel,
        result.reversed_count,
        result.isolated_count,
        result.max_jump_distance.round(1),
        result.large_jump_count,
        result.connection_jump_max.round(1),
        result.connection_large_jump_count,
        result.connection_count,
        result.flat_coords.size,
        ordered.size,
        backward_turns
      ]
      progress.increment
    end

    # backward_turns 降順 → 採番が壊れている路線を上から見られるようにする。
    rows.sort_by! { |row| [ -row[13], -row[8] ] }

    CSV.open(out_path, "w") do |csv|
      csv << %w[
        bus_route_id name total_tracks skipped_parallel reversed_count isolated_count
        max_jump_m large_jump_count connection_jump_max_m connection_large_jump_count
        connection_count flat_coords_size bus_stop_count backward_turns
      ]
      rows.each { |row| csv << row }
    end

    total_routes = rows.size
    routes_with_skipped = rows.count { |r| r[3] > 0 }
    routes_with_reversed = rows.count { |r| r[4] > 0 }
    routes_with_isolated = rows.count { |r| r[5] > 0 }
    routes_with_conn_large_jump = rows.count { |r| r[9] > 0 }
    routes_with_backward = rows.count { |r| r[13] > 0 }
    total_backward = rows.sum { |r| r[13] }
    puts ""
    puts "Wrote #{out_path}"
    puts "Total routes:                       #{total_routes}"
    puts "Routes with skipped parallel:       #{routes_with_skipped}"
    puts "Routes with reversed track:         #{routes_with_reversed}"
    puts "Routes with isolated track:         #{routes_with_isolated}"
    puts "Routes with >100m connection jump:  #{routes_with_conn_large_jump}"
    puts "Routes with backward turns (採番):  #{routes_with_backward}"
    puts "Total backward turns (合計):        #{total_backward}"
    puts ""
    puts "Top 10 by backward_turns (採番の逆走が多い順):"
    puts "  #{'route_id'.ljust(8)} #{'backward'.ljust(10)} #{'stops'.ljust(7)} #{'conn_jump_m'.ljust(13)} name"
    rows.first(10).each do |row|
      puts "  #{row[0].to_s.ljust(8)} #{row[13].to_s.ljust(10)} #{row[12].to_s.ljust(7)} #{row[8].to_s.ljust(13)} #{row[1]}"
    end
  end

  desc "Inspect a single route's stitch + bus_stop_number assignment (ROUTE_ID=...)"
  task inspect: :environment do
    route_id = Integer(ENV.fetch("ROUTE_ID"))
    bus_route = BusRoute.find(route_id)
    tracks = bus_route.bus_route_tracks.to_a

    puts "Route ##{bus_route.id}: #{bus_route.operation_company} #{bus_route.line_name}"
    puts "  bus_type: #{bus_route.bus_type}"
    puts ""

    puts "Tracks (#{tracks.size}):"
    tracks.each do |t|
      puts "  ##{t.id} coords=#{t.coordinates.size} head=#{t.coordinates.first.inspect} tail=#{t.coordinates.last.inspect}"
    end
    puts ""

    result = TrackStitcher.call_with_diagnostics(tracks)
    puts "Stitch summary:"
    puts "  total_tracks: #{result.total_tracks}, skipped_parallel: #{result.skipped_parallel}"
    puts "  reversed_count: #{result.reversed_count}, isolated_count: #{result.isolated_count}"
    puts "  flat_coords_size: #{result.flat_coords.size}"
    puts "  max_jump (track内+連結部): #{result.max_jump_distance.round(1)}m"
    puts "  connection_jump_max: #{result.connection_jump_max.round(1)}m  (connection_count=#{result.connection_count})"
    puts ""

    puts "Stitch steps:"
    result.stitch_steps.each_with_index do |step, i|
      flag = step.isolated ? "[isolated]" : (step.reversed ? "[reversed]" : "")
      puts "  step #{(i + 1).to_s.rjust(2)}: track ##{step.track_id} coords=#{step.coords_size} join=#{step.join_distance.round(1)}m #{flag}"
    end
    puts ""

    brbs = bus_route.bus_route_bus_stops.includes(:bus_stop).order(:bus_stop_number, :id).to_a
    flat = result.flat_coords
    puts "Bus stops (#{brbs.size}, ordered by bus_stop_number):"
    brbs.each do |b|
      bs = b.bus_stop
      min_idx = 0
      min_dist = Float::INFINITY
      flat.each_with_index do |c, idx|
        d = (bs.latitude - c[0]) ** 2 + (bs.longitude - c[1]) ** 2
        if d < min_dist
          min_dist = d
          min_idx = idx
        end
      end
      num = b.bus_stop_number ? b.bus_stop_number.to_s.rjust(3) : "  -"
      puts "  ##{num}  brbs=#{b.id.to_s.ljust(8)} stop=#{bs.name.to_s.ljust(28)} closest_idx=#{min_idx.to_s.rjust(5)}/#{flat.size}  lat=#{bs.latitude.round(5)} lng=#{bs.longitude.round(5)}"
    end
  end

  desc "Load bus_stop_number from db/data/bus_stop_numbers.csv"
  task load: :environment do
    csv_path = "db/data/bus_stop_numbers.csv"
    raise "Missing #{csv_path}. Run 'rails bus_stop_number:generate' first." unless File.exist?(csv_path)

    raw = ActiveRecord::Base.connection.raw_connection
    ActiveRecord::Base.transaction do
      # temp table 経由の bulk UPDATE。
      # ON COMMIT DROP でトランザクション終了時に自動廃棄される。
      raw.exec("CREATE TEMP TABLE _tmp_bsn (bus_route_bus_stop_id INTEGER, bus_stop_number INTEGER) ON COMMIT DROP")

      raw.copy_data("COPY _tmp_bsn (bus_route_bus_stop_id, bus_stop_number) FROM STDIN WITH CSV HEADER") do
        File.open(csv_path, "r") do |f|
          while (line = f.gets)
            raw.put_copy_data(line)
          end
        end
      end

      # 1 SQL で全件 UPDATE。AR の save 経由（行ごとに UPDATE 発行）と比べて桁違いに速い。
      raw.exec(<<~SQL)
        UPDATE bus_route_bus_stops AS brbs
        SET bus_stop_number = t.bus_stop_number
        FROM _tmp_bsn AS t
        WHERE brbs.id = t.bus_route_bus_stop_id
      SQL
    end
    puts "Loaded #{csv_path}"
  end
end
