# 路線の bus_route_tracks を 1 本の flat_coords に連結する `stitch:generate` を提供する。
#
# 出力: db/data/stitches.csv.gz (per-route × 起点候補 (A: selector / B: nil) で 1 〜 2 行)。
# bus_stop_number:generate / diagnose はこのファイルを読み出し、stitcher を再実行せずに
# numberer + 評価だけを回す。
#
# stitch:load は無い: production はこの中間ファイルを読まない (DB のスキーマは無変更)。
# Heroku デプロイでも generate は呼ばれず、commit 済みの CSV を bus_stop_number:load の
# 直前段階として bus_stop_number:generate (= ローカル実行) が消費するだけ。
require "etc"

namespace :stitch do
  # generate / profile から共通に呼ぶ計算本体。Hash {(route_id, start_repr) => Entry} を返す。
  # pick_best_assignment と同じ start 候補 (selector A + fallback nil) を全 route で計算する。
  #
  # per-route 処理は独立なので fork-based 並列で worker 数倍速くなる。
  # STITCH_WORKERS env で worker 数を上書き可能 (default = Etc.nprocessors)。
  def self.compute_stitches
    scope = PrefectureFilter.apply(BusRoute.with_fragmented)
    bus_route_ids = scope.pluck(:id)
    # default = nprocessors - 1 (= parent process + db / docker daemon 用に 1 CPU 残す)。
    # VM 全 CPU を worker で奪い合うと context switching が増えてかえって遅くなる。
    worker_count = ENV.fetch("STITCH_WORKERS") { [ Etc.nprocessors - 1, 1 ].max }.to_i

    results = if worker_count <= 1 || bus_route_ids.size <= worker_count
      # 1 worker のときは fork overhead を払わず in-process で回す。
      [ compute_stitches_for(bus_route_ids) ]
    else
      # 自前 Process.fork で並列化する。子→親のデータ転送は file 経由で行う
      # (parallel gem は子の cleanup hook で hang するケースがあったため独自実装に切り替え)。
      require "fileutils"
      require "securerandom"
      ActiveRecord::Base.connection_handler.connection_pools.each(&:disconnect!)
      chunk_size = (bus_route_ids.size.to_f / worker_count).ceil
      chunks = bus_route_ids.each_slice(chunk_size).to_a
      tmp_dir = "tmp/_parallel_stitches_#{SecureRandom.hex(4)}"
      FileUtils.mkdir_p(tmp_dir)

      pids = chunks.each_with_index.map do |ids_chunk, idx|
        Process.fork do
          # 子プロセスは親から継承した PG socket を共有してしまい、デッドロックの原因になる。
          ActiveRecord::Base.connection_handler.connection_pools.each(&:disconnect!)
          partial = compute_stitches_for(ids_chunk)
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

    map = {}
    selector_used = 0
    fallback_only = 0
    results.each do |partial|
      map.merge!(partial[:map])
      selector_used += partial[:selector_used]
      fallback_only += partial[:fallback_only]
    end
    puts "  selector picked start_a: #{selector_used}, fallback only: #{fallback_only} (#{worker_count} workers)"
    map
  end

  # 指定 route IDs の chunk 分を計算。並列 worker 内 / シリアル両方から呼ぶ。
  def self.compute_stitches_for(bus_route_ids)
    map = {}
    selector_used = 0
    fallback_only = 0

    ActiveRecord::Base.logger.silence(Logger::WARN) do
      BusRoute.with_fragmented
              .where(id: bus_route_ids)
              .includes(:bus_route_tracks, bus_route_bus_stops: :bus_stop)
              .find_each do |bus_route|
        tracks = bus_route.bus_route_tracks.to_a
        # in-memory sort (preload 済みの association を reorder で再クエリしない)。
        brbs = bus_route.bus_route_bus_stops.sort_by(&:id)
        start_a = StartTerminalSelector.call(
          tracks,
          line_name: bus_route.line_name,
          bus_route_bus_stops: brbs,
          stitch_fn: ->(t, s) {
            key = [ bus_route.id, StitchStore.encode_start(s) ]
            map[key] ||= StitchStore.entry_from_result(stitch_one(t, s))
            StitchStore.result_from_entry(map[key])
          }
        )

        # 候補 B = westmost fallback (start: nil)。常に持っておく。
        b_key = [ bus_route.id, StitchStore.encode_start(nil) ]
        map[b_key] ||= StitchStore.entry_from_result(stitch_one(tracks, nil))

        if start_a
          a_key = [ bus_route.id, StitchStore.encode_start(start_a) ]
          map[a_key] ||= StitchStore.entry_from_result(stitch_one(tracks, start_a))
          selector_used += 1
        else
          fallback_only += 1
        end
      end
    end

    { map: map, selector_used: selector_used, fallback_only: fallback_only }
  end

  # stitcher 1 回呼び出しの薄いラッパ。プロファイル時にここを起点に時間を測る用。
  def self.stitch_one(tracks, start)
    TrackStitcher.call_with_diagnostics(tracks, start: start)
  end

  desc "Stitch all routes' bus_route_tracks into db/data/stitches.csv.gz (does not touch DB). PREFECTURE=東京都 で 1 県だけ再計算し既存 CSV にマージ (CSV は常に 47 都道府県分完全)"
  task generate: :environment do
    $stdout.sync = true
    new_map = compute_stitches
    if PrefectureFilter.active?
      # 既存 CSV を load → 該当県の route_ids の entries を一旦削除 (旧 start_repr の orphan を残さない)
      # → 新 entries をマージ → 書き戻し。これで CSV は常に 47 都道府県分完全な状態を保つ。
      tokyo_route_ids = new_map.keys.map(&:first).to_set
      existing_map = StitchStore.load_existing
      existing_map.delete_if { |(rid, _), _| tokyo_route_ids.include?(rid) }
      merged = existing_map.merge(new_map)
      path = StitchStore.write(merged)
      puts "PREFECTURE filter: replaced stitches for #{tokyo_route_ids.size} routes (#{new_map.size} entries) -> #{path} (total #{merged.size})"
    else
      path = StitchStore.write(new_map)
      puts "Wrote #{path} (#{new_map.size} entries)"
    end
  end

  desc "Profile stitch:generate via stackprof (writes tmp/stitch_generate.stackprof). STITCH_WORKERS=1 で in-process プロファイル可能"
  task profile: :environment do
    require "stackprof"

    $stdout.sync = true
    out = "tmp/stitch_generate.stackprof"
    StackProf.run(mode: :wall, out: out, interval: 1000) do
      compute_stitches
    end
    puts ""
    puts "Profile saved to #{out}"
    puts "View top by self time:   bundle exec stackprof #{out} --text --limit 30"
    puts "View top by total time:  bundle exec stackprof #{out} --text --total --limit 30"
  end
end
