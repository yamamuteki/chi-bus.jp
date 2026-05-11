# 路線の bus_route_tracks を 1 本の flat_coords に連結する `stitch:generate` を提供する。
#
# 出力: db/data/stitches.csv.gz (per-route × 起点候補 (A: selector / B: nil) で 1 〜 2 行)。
# bus_stop_number:generate / diagnose はこのファイルを読み出し、stitcher を再実行せずに
# numberer + 評価だけを回す。
#
# stitch:load は無い: production はこの中間ファイルを読まない (DB のスキーマは無変更)。
# Heroku デプロイでも generate は呼ばれず、commit 済みの CSV を bus_stop_number:load の
# 直前段階として bus_stop_number:generate (= ローカル実行) が消費するだけ。
namespace :stitch do
  # generate / profile から共通に呼ぶ計算本体。Hash {(route_id, start_repr) => Entry} を返す。
  # pick_best_assignment と同じ start 候補 (selector A + fallback nil) を全 route で計算する。
  def self.compute_stitches
    map = {}
    selector_used = 0
    fallback_only = 0
    multi_try = 0
    fallback_multi = ->(tracks, start) {
      multi_try += 1
      stitch_one(tracks, start)
    }

    scope = PrefectureFilter.apply(BusRoute.with_fragmented)

    ActiveRecord::Base.logger.silence(Logger::WARN) do
      scope.find_each do |bus_route|
        tracks = bus_route.bus_route_tracks.to_a
        # selector の駅 hint や line_name hint で起点候補 A を決める。
        # multi_try_min_bridge にハマったときも内部で stitch を使うので、その分も map に乗せる。
        brbs = bus_route.bus_route_bus_stops.reorder(:id).includes(:bus_stop).to_a
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

    puts "  selector picked start_a: #{selector_used}, fallback only: #{fallback_only}, multi_try fires: #{multi_try}"
    map
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

  desc "Profile stitch:generate via stackprof (writes tmp/stitch_generate.stackprof)"
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
