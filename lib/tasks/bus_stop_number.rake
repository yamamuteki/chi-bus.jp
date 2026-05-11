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
  # AR (BusStop.latitude 等) は LazyAttributeSet#fetch_value 経由で旧プロファイル上 21% 占めて
  # いた。numberer / orienter / selector / diagnose は brbs.id / brbs.bus_stop_number /
  # brbs.bus_stop.{latitude,longitude,name} しか触らないので、AR の代わりに plain Struct で
  # wrap して JOIN 1 本の pluck で必要列だけロードする。
  PluckedBrbs = Struct.new(:id, :bus_stop_number, :bus_stop, keyword_init: true)
  PluckedBusStop = Struct.new(:latitude, :longitude, :name, keyword_init: true)

  # 1 路線分の brbs を bus_stops JOIN ＋ pluck で軽量にロードする。
  # AR インスタンス化を避け、attribute 読み出しを Struct 化することで hot loop の overhead を削減。
  def self.load_brbs(bus_route)
    bus_route.bus_route_bus_stops
             .joins(:bus_stop)
             .reorder("bus_route_bus_stops.id")
             .pluck(
               "bus_route_bus_stops.id",
               "bus_route_bus_stops.bus_stop_number",
               "bus_stops.latitude",
               "bus_stops.longitude",
               "bus_stops.name"
             )
             .map { |id, num, lat, lng, name|
               PluckedBrbs.new(
                 id: id,
                 bus_stop_number: num,
                 bus_stop: PluckedBusStop.new(latitude: lat, longitude: lng, name: name)
               )
             }
  end

  # generate / profile から共通に呼ぶ計算本体。CSV に書き出す行配列を返す。
  #
  # 6000+ 路線 × N クエリの構成のため、開発環境の SQL クエリログ生成
  # (BacktraceCleaner + Thread.each_caller_location) がプロファイル上 30%+ を占める。
  # silence で WARN 以上に絞ると generate 全体が 30% ほど短縮される。
  # 路線 1 つに対して採番結果一式 (assignments / flat_coords / 各種 diagnostic 構造) を返す。
  # 内部で「StartTerminalSelector 起点版」と「westmost fallback 版」を両方計算し、
  # idx 上の inversion が少ない方を採用する。selector が起点を決められない場合 (terminal 1 つ
  # 以下 / cycle) は 1 回だけ stitch する。
  #
  # 戻り値の :stitch / :number_result はすべて picked path のもの。compute_assignments と
  # diagnose の両方で同じ選択結果を扱うために共通化している。
  # stitch:generate が出力した db/data/stitches.csv.gz から該当 route の stitch を引き、
  # numberer + LineNameOrienter で採番する。stitches に該当行が無ければ stitcher を live 実行
  # (= stitch:generate 後に DB へ新規 route が追加されたケース等の救済)。
  def self.pick_best_assignment(bus_route, brbs, stitches)
    tracks = bus_route.bus_route_tracks.to_a
    start_a = StartTerminalSelector.call(
      tracks,
      line_name: bus_route.line_name,
      bus_route_bus_stops: brbs,
      stitch_fn: ->(t, s) { fetch_stitch(stitches, bus_route.id, t, s) }
    )

    if start_a.nil?
      return run_pipeline(tracks, bus_route, brbs, start: nil, fallback: false, stitches: stitches)
    end

    candidate_a = run_pipeline(tracks, bus_route, brbs, start: start_a, fallback: false, stitches: stitches)
    candidate_b = run_pipeline(tracks, bus_route, brbs, start: nil, fallback: true, stitches: stitches)

    # vertex_indices は numberer が射影ループ内で計算済み (BusStopNumberer::Result.vertex_indices)。
    # flat_coords を再走査しないので 1 route あたり O(brbs × coords) を 2 回節約できる。
    inv_a = count_inversions(candidate_a[:number_result].vertex_indices, brbs, candidate_a[:assignments])
    inv_b = count_inversions(candidate_b[:number_result].vertex_indices, brbs, candidate_b[:assignments])

    # A 優位 or 同点なら A (selector のメリットを残す)。B が明確に良ければ fallback。
    # 過去観察: selector は bridge 距離合計を最小化するが、それが順序最良と一致しないケースが
    # 935 路線あった (例: 石見銀山号 1→30、祖谷線 0→22)。inversion 多い方を捨てる安全網。
    inv_a <= inv_b ? candidate_a : candidate_b
  end

  # numberer + LineNameOrienter を 1 回回し、後続評価のため stitch/number_result も返す。
  # stitch は stitches store から引く (live 実行は fetch_stitch のフォールバックパス)。
  def self.run_pipeline(tracks, bus_route, brbs, start:, fallback:, stitches:)
    stitch = fetch_stitch(stitches, bus_route.id, tracks, start)
    number_result = BusStopNumberer.call_with_diagnostics(
      flat_coords: stitch.flat_coords,
      bus_route_bus_stops: brbs,
      bridge_segment_indices: stitch.bridge_segment_indices
    )
    oriented = LineNameOrienter.call(bus_route, brbs, number_result.assignments)
    {
      stitch: stitch,
      number_result: number_result,
      flat_coords: stitch.flat_coords,
      assignments: oriented,
      fallback: fallback
    }
  end

  # stitches store から該当 (route_id, start) の stitch を引く。
  # 無ければ stitcher を live 実行して store に追記する (stitch:generate 以降に DB へ新規 route が
  # 入ったケース等)。store が完全に空なら stitch:generate の実行漏れを示すので明示的に raise する。
  def self.fetch_stitch(stitches, route_id, tracks, start)
    key = [ route_id, StitchStore.encode_start(start) ]
    if (entry = stitches[key])
      StitchStore.result_from_entry(entry)
    else
      result = TrackStitcher.call_with_diagnostics(tracks, start: start)
      stitches[key] = StitchStore.entry_from_result(result)
      result
    end
  end

  # per-route 採番処理を並列化する。NUMBER_WORKERS env で worker 数を上書き可能 (default = Etc.nprocessors)。
  # with_diagnostics: true で診断用 quality metrics も同時計算する (= diagnose task の重複計算を回避)。
  def self.compute_assignments(with_diagnostics: false)
    require "etc"
    stitches = StitchStore.load_existing
    if stitches.empty?
      raise "Missing #{StitchStore.path}. Run 'rails stitch:generate' first."
    end
    initial_size = stitches.size
    puts "  stitches loaded: #{initial_size} entries from #{StitchStore.path}"

    scope = PrefectureFilter.apply(BusRoute.with_fragmented)
    bus_route_ids = scope.pluck(:id)
    # default = nprocessors - 1 (= parent process + db / docker daemon 用に 1 CPU 残す)。
    # VM 全 CPU を worker で奪い合うと context switching が増えてかえって遅くなる。
    worker_count = ENV.fetch("NUMBER_WORKERS") { [ Etc.nprocessors - 1, 1 ].max }.to_i

    results = if worker_count <= 1 || bus_route_ids.size <= worker_count
      # 1 worker のときは fork overhead を払わず in-process で回す。
      [ compute_assignments_for(bus_route_ids, stitches, with_diagnostics: with_diagnostics) ]
    else
      # 自前 Process.fork で並列化する。parallel gem は子の Marshal-pipe 経由の結果転送で
      # 中規模 (diag_rows 8MB 級) でも子の exit を detect できず親が wait に張り付くケースが
      # あったため、parent からは control だけ持ち、子→親のデータ転送は file 経由にする。
      require "fileutils"
      require "securerandom"
      ActiveRecord::Base.connection_handler.connection_pools.each(&:disconnect!)
      chunk_size = (bus_route_ids.size.to_f / worker_count).ceil
      chunks = bus_route_ids.each_slice(chunk_size).to_a
      tmp_dir = "tmp/_parallel_assignments_#{SecureRandom.hex(4)}"
      FileUtils.mkdir_p(tmp_dir)

      pids = chunks.each_with_index.map do |ids_chunk, idx|
        Process.fork do
          # 子プロセスは親から継承した PG socket を共有してしまい、デッドロックの原因になる。
          # disconnect! で stale connection を切り、次のクエリで新規確立させる。
          ActiveRecord::Base.connection_handler.connection_pools.each(&:disconnect!)
          local_stitches = StitchStore.load_existing
          partial = compute_assignments_for(ids_chunk, local_stitches, with_diagnostics: with_diagnostics)
          File.binwrite(File.join(tmp_dir, "#{idx}.dump"), Marshal.dump(partial))
          # exit! で at_exit hook / AR の after_fork hook 等のクリーンアップを skip し
          # 確実に終了させる (= 通常の exit だと親と共有する socket の close で hang する)。
          exit!(0)
        end
      end
      pids.each { |pid| Process.waitpid(pid) }

      chunks.each_with_index.map do |_, idx|
        path = File.join(tmp_dir, "#{idx}.dump")
        partial = Marshal.load(File.binread(path))
        File.delete(path)
        partial
      end.tap { FileUtils.rm_rf(tmp_dir) }
    end

    rows = []
    diag_rows = []
    fallback_count = 0
    new_stitch_count = 0
    results.each do |partial|
      rows.concat(partial[:rows])
      diag_rows.concat(partial[:diag_rows]) if with_diagnostics
      fallback_count += partial[:fallback_count]
      new_stitch_count += partial[:new_stitch_count]
    end

    if new_stitch_count > 0
      puts "  stitches: +#{new_stitch_count} live-stitched entries (route 新規追加? stitch:generate を再実行推奨)"
    end

    rows.sort_by! { |id, _| id }
    puts "  fallback to westmost: #{fallback_count} routes (#{worker_count} workers)"
    with_diagnostics ? { rows: rows, diag_rows: diag_rows } : rows
  end

  # bus_route_ids の chunk 分を採番する。並列 worker 内 / シリアル両方から呼ぶ。
  def self.compute_assignments_for(bus_route_ids, stitches, with_diagnostics: false)
    initial_size = stitches.size
    rows = []
    diag_rows = []
    fallback_count = 0

    ActiveRecord::Base.logger.silence(Logger::WARN) do
      BusRoute.with_fragmented.where(id: bus_route_ids).find_each do |bus_route|
        brbs = load_brbs(bus_route)
        result = pick_best_assignment(bus_route, brbs, stitches)
        rows.concat(result[:assignments])
        fallback_count += 1 if result[:fallback]

        if with_diagnostics
          # brbs に新採番を inject してから quality metrics を計算する
          # (stored bus_stop_number ではなく今 picked した結果で順序評価)。
          num_by_id = result[:assignments].to_h
          brbs.each { |b| b.bus_stop_number = num_by_id[b.id] }
          diag_rows << build_diagnose_row(bus_route, brbs, result[:stitch], result[:number_result])
        end
      end
    end

    { rows: rows, diag_rows: diag_rows, fallback_count: fallback_count,
      new_stitch_count: stitches.size - initial_size }
  end

  # bus_stop_number 順に並べたバス停の「flat_coords 上での最近接 vertex idx」が単調か。
  # 5 idx 以上戻ったら inversion とカウントする (SimplifyRb の小ぶれを許容)。
  # diagnose タスクの idx_inversions と同じ計算 (こちらは A/B 比較で 2 回呼ばれる)。
  #
  # vertex_indices は BusStopNumberer::Result.vertex_indices (= 各 brbs の最近接 vertex の
  # flat_coords 内 index)。numberer の射影ループに乗せて計算済みなので、ここでは flat_coords
  # を再走査しない。
  def self.count_inversions(vertex_indices, brbs, assignments)
    num_by_id = assignments.to_h
    ordered = brbs.map { |b| [ b, num_by_id[b.id] ] }
                  .select { |_, n| n }
                  .sort_by { |_, n| n }
    inversions = 0
    prev_idx = -1
    ordered.each do |b, _|
      min_idx = vertex_indices[b.id]
      next if min_idx.nil?
      inversions += 1 if prev_idx >= 0 && min_idx < prev_idx - 5
      prev_idx = min_idx
    end
    inversions
  end

  # 2 点間の haversine 距離 (m)。diagnose で連続バス停間の距離評価に使う。
  HAVERSINE = ->(lat1, lng1, lat2, lng2) {
    rad = Math::PI / 180.0
    dlat = (lat2 - lat1) * rad
    dlng = (lng2 - lng1) * rad
    a = Math.sin(dlat / 2.0) ** 2 +
        Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dlng / 2.0) ** 2
    2.0 * 6_371_000.0 * Math.asin(Math.sqrt(a))
  }

  # 1 路線分の diagnose row (CSV カラム順) を返す。
  # brbs_list は事前に bus_stop_number を inject 済みである前提 (compute_assignments_for で setup)。
  DIAGNOSE_OFF_TRACK_THRESHOLD_M = 200.0
  def self.build_diagnose_row(bus_route, brbs_list, stitch, number_result)
    off_track_count = 0
    off_track_max_m = 0.0
    number_result.distances_m.each_value do |dist|
      next if dist.nil?
      off_track_count += 1 if dist > DIAGNOSE_OFF_TRACK_THRESHOLD_M
      off_track_max_m = dist if dist > off_track_max_m
    end

    ordered = brbs_list.select { |b| b.bus_stop_number }.sort_by(&:bus_stop_number)
    backward_turns = 0
    ordered.each_cons(3) do |a, b, c|
      ab_lat = b.bus_stop.latitude - a.bus_stop.latitude
      ab_lng = b.bus_stop.longitude - a.bus_stop.longitude
      bc_lat = c.bus_stop.latitude - b.bus_stop.latitude
      bc_lng = c.bus_stop.longitude - b.bus_stop.longitude
      dot = ab_lat * bc_lat + ab_lng * bc_lng
      backward_turns += 1 if dot < 0
    end

    idx_inversions = 0
    vertex_indices = number_result.vertex_indices
    prev_idx = -1
    ordered.each do |b|
      min_idx = vertex_indices[b.id]
      next if min_idx.nil?
      idx_inversions += 1 if prev_idx >= 0 && min_idx < prev_idx - 5
      prev_idx = min_idx
    end

    distances_m = ordered.each_cons(2).map { |a, b|
      HAVERSINE.call(a.bus_stop.latitude, a.bus_stop.longitude,
                     b.bus_stop.latitude, b.bus_stop.longitude)
    }
    anomaly_jumps = 0
    consec_max_m = 0.0
    median_m = 0.0
    if !distances_m.empty?
      consec_max_m = distances_m.max
      sorted_d = distances_m.sort
      median_m = sorted_d[sorted_d.size / 2]
      threshold_m = [ 500.0, median_m * 3 ].max
      anomaly_jumps = distances_m.count { |d| d > threshold_m }
    end

    [
      bus_route.id,
      "#{bus_route.operation_company} #{bus_route.line_name}".strip,
      stitch.total_tracks,
      stitch.skipped_parallel,
      stitch.reversed_count,
      stitch.isolated_count,
      stitch.max_jump_distance.round(1),
      stitch.large_jump_count,
      stitch.connection_jump_max.round(1),
      stitch.connection_large_jump_count,
      stitch.connection_count,
      stitch.flat_coords.size,
      ordered.size,
      backward_turns,
      off_track_count,
      off_track_max_m.round(1),
      idx_inversions,
      anomaly_jumps,
      consec_max_m.round(1),
      median_m.round(1)
    ]
  end

  # diagnose 結果を CSV + サマリ表示。generate WITH_DIAGNOSTICS=1 と diagnose task の両方から呼ぶ。
  def self.write_diagnose_results(rows, out_path)
    require "csv"
    # anomaly_jumps 降順 → median ベースで「飛び」が異常に多い路線を上から見られる。
    rows.sort_by! { |row| [ -row[17], -row[18] ] }
    CSV.open(out_path, "w") do |csv|
      csv << %w[
        bus_route_id name total_tracks skipped_parallel reversed_count isolated_count
        max_jump_m large_jump_count connection_jump_max_m connection_large_jump_count
        connection_count flat_coords_size bus_stop_count backward_turns
        off_track_count off_track_max_m idx_inversions anomaly_jumps consec_max_m median_m
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
    routes_with_off_track = rows.count { |r| r[14] > 0 }
    total_off_track = rows.sum { |r| r[14] }
    routes_with_inversions = rows.count { |r| r[16] > 0 }
    total_inversions = rows.sum { |r| r[16] }
    routes_with_anomaly = rows.count { |r| r[17] > 0 }
    total_anomaly = rows.sum { |r| r[17] }
    puts ""
    puts "Wrote #{out_path}"
    puts "Total routes:                       #{total_routes}"
    puts "Routes with skipped parallel:       #{routes_with_skipped}"
    puts "Routes with reversed track:         #{routes_with_reversed}"
    puts "Routes with isolated track:         #{routes_with_isolated}"
    puts "Routes with >100m connection jump:  #{routes_with_conn_large_jump}"
    puts "Routes with backward turns (採番):  #{routes_with_backward}"
    puts "Total backward turns (合計):        #{total_backward}"
    puts "Routes with off-track (>#{DIAGNOSE_OFF_TRACK_THRESHOLD_M.to_i}m) bus stops:  #{routes_with_off_track}"
    puts "Total off-track bus stops (合計):   #{total_off_track}"
    puts "Routes with idx inversions:         #{routes_with_inversions}"
    puts "Total idx inversions (合計):        #{total_inversions}"
    puts "Routes with anomaly jumps:          #{routes_with_anomaly}"
    puts "Total anomaly jumps (合計):         #{total_anomaly}"
    puts ""
    puts "Top 20 by anomaly_jumps (median 比 3 倍超の飛びが多い順 - 真の採番崩れ):"
    puts "  #{'route_id'.ljust(8)} #{'anom'.ljust(5)} #{'maxm'.ljust(8)} #{'med'.ljust(7)} #{'inv'.ljust(5)} #{'stops'.ljust(7)} name"
    rows.first(20).each do |row|
      puts "  #{row[0].to_s.ljust(8)} #{row[17].to_s.ljust(5)} #{row[18].to_s.ljust(8)} #{row[19].to_s.ljust(7)} #{row[16].to_s.ljust(5)} #{row[12].to_s.ljust(7)} #{row[1]}"
    end
  end

  desc "Generate bus_stop_number into db/data/bus_stop_numbers.csv.gz (does not touch DB). PREFECTURE=東京都 で 1 県だけ再計算し既存 CSV にマージ (CSV は常に 47 都道府県分完全、DB 反映には bus_stop_number:load を続けて呼ぶ)。WITH_DIAGNOSTICS=1 で tmp/bus_stop_number_diagnostics.csv も同時生成 (= diagnose task 別実行を不要にする)"
  task generate: :environment do
    require "csv"
    require "zlib"
    $stdout.sync = true
    csv_path = "db/data/bus_stop_numbers.csv.gz"
    with_diagnostics = !ENV["WITH_DIAGNOSTICS"].to_s.empty?

    # 1. db/data/stitches.csv.gz から stitch 結果を読み込む (stitch:generate 出力)。
    # 2. BusStopNumberer で各 brbs に bus_stop_number を割り当て、A/B 候補から best を選ぶ。
    # 3. WITH_DIAGNOSTICS=1 のとき: 採番と同時に品質指標も計算 (per-route ループ内で完結、
    #    bus_stop_number:diagnose の重複計算を回避)。
    result = compute_assignments(with_diagnostics: with_diagnostics)
    rows = with_diagnostics ? result[:rows] : result

    if PrefectureFilter.active?
      # 既存 CSV を load → 該当県の brbs を更新 (= 他 46 県の rows はそのまま) → 書き戻し。
      # これで CSV は常に 47 都道府県分完全。DB 反映は bus_stop_number:load を続けて呼ぶ。
      existing = load_existing_assignments(csv_path)
      rows.each { |id, num| existing[id] = num }
      sorted = existing.sort.to_a
      Zlib::GzipWriter.open(csv_path) do |gz|
        csv = CSV.new(gz, headers: %w[bus_route_bus_stop_id bus_stop_number], write_headers: true)
        sorted.each { |row| csv << row }
      end
      puts "PREFECTURE filter: merged #{rows.size} rows into #{csv_path} (total #{sorted.size}). Run 'bus_stop_number:load' to apply to DB."
    else
      Zlib::GzipWriter.open(csv_path) do |gz|
        csv = CSV.new(gz, headers: %w[bus_route_bus_stop_id bus_stop_number], write_headers: true)
        rows.each { |row| csv << row }
      end
      puts "Wrote #{csv_path} (#{rows.size} rows)"
    end

    if with_diagnostics
      diag_path = "tmp/bus_stop_number_diagnostics.csv"
      diag_rows = result[:diag_rows]
      # compute_assignments は with_fragmented で回す → INCLUDE_FRAGMENTED 未指定なら fragmented 除外。
      unless ENV["INCLUDE_FRAGMENTED"]
        fragmented_ids = BusRoute.where(fragmented: true).pluck(:id).to_set
        diag_rows = diag_rows.reject { |row| fragmented_ids.include?(row[0]) }
      end
      write_diagnose_results(diag_rows, diag_path)
    end
  end

  # 既存 bus_stop_numbers.csv.gz を Hash{brbs_id => bus_stop_number} で読み込む。
  # PREFECTURE filter で部分更新する際に「他 46 県分」を保持するために使う。
  def self.load_existing_assignments(csv_path)
    return {} unless File.exist?(csv_path)
    map = {}
    Zlib::GzipReader.open(csv_path) do |f|
      CSV.new(f, headers: true).each do |row|
        num = row["bus_stop_number"]
        map[row["bus_route_bus_stop_id"].to_i] = num.nil? || num.empty? ? nil : num.to_i
      end
    end
    map
  end

  desc "Profile bus_stop_number:generate via stackprof (writes tmp/bus_stop_number_generate.stackprof)"
  task profile: :environment do
    require "stackprof"

    $stdout.sync = true
    out = "tmp/bus_stop_number_generate.stackprof"
    StackProf.run(mode: :wall, out: out, interval: 1000) do
      compute_assignments
    end
    puts ""
    puts "Profile saved to #{out}"
    puts "View top by self time:   bundle exec stackprof #{out} --text --limit 30"
    puts "View top by total time:  bundle exec stackprof #{out} --text --total --limit 30"
  end

  desc "Diagnose TrackStitcher quality per route into tmp/bus_stop_number_diagnostics.csv (set INCLUDE_FRAGMENTED=1 to include fragmented routes). 内部で compute_assignments(with_diagnostics: true) を呼ぶ (= generate と同じ並列化された経路で品質指標を計算)"
  task diagnose: :environment do
    $stdout.sync = true
    out_path = "tmp/bus_stop_number_diagnostics.csv"

    result = compute_assignments(with_diagnostics: true)
    rows = result[:diag_rows]

    unless ENV["INCLUDE_FRAGMENTED"]
      fragmented_ids = BusRoute.where(fragmented: true).pluck(:id).to_set
      rows = rows.reject { |row| fragmented_ids.include?(row[0]) }
    end

    scope_label = ENV["INCLUDE_FRAGMENTED"] ? "INCLUDING" : "EXCLUDING"
    puts "Diagnose target: #{rows.size} routes (#{scope_label} fragmented)"
    write_diagnose_results(rows, out_path)
  end


  desc "Inspect a single route's stitch + bus_stop_number assignment (ROUTE_ID=...)"
  task inspect: :environment do
    route_id = Integer(ENV.fetch("ROUTE_ID"))
    bus_route = BusRoute.with_fragmented.find(route_id)
    tracks = bus_route.bus_route_tracks.to_a

    puts "Route ##{bus_route.id}: #{bus_route.operation_company} #{bus_route.line_name}"
    puts "  bus_type: #{bus_route.bus_type}"
    puts ""

    puts "Tracks (#{tracks.size}):"
    tracks.each do |t|
      puts "  ##{t.id} coords=#{t.coordinates.size} head=#{t.coordinates.first.inspect} tail=#{t.coordinates.last.inspect}"
    end
    puts ""

    brbs_for_start = bus_route.bus_route_bus_stops.includes(:bus_stop).to_a
    start = StartTerminalSelector.call(tracks, line_name: bus_route.line_name, bus_route_bus_stops: brbs_for_start)
    puts "Start selection:"
    puts "  picked: #{start.inspect}  (nil = TrackStitcher 最西端 fallback)"
    puts ""

    result = TrackStitcher.call_with_diagnostics(tracks, start: start)
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

  desc "Load bus_stop_number from db/data/bus_stop_numbers.csv.gz"
  task load: :environment do
    require "zlib"
    csv_path = "db/data/bus_stop_numbers.csv.gz"
    raise "Missing #{csv_path}. Run 'rails bus_stop_number:generate' first." unless File.exist?(csv_path)

    raw = ActiveRecord::Base.connection.raw_connection
    ActiveRecord::Base.transaction do
      # temp table 経由の bulk UPDATE。
      # ON COMMIT DROP でトランザクション終了時に自動廃棄される。
      raw.exec("CREATE TEMP TABLE _tmp_bsn (bus_route_bus_stop_id INTEGER, bus_stop_number INTEGER) ON COMMIT DROP")

      raw.copy_data("COPY _tmp_bsn (bus_route_bus_stop_id, bus_stop_number) FROM STDIN WITH CSV HEADER") do
        Zlib::GzipReader.open(csv_path) do |f|
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
