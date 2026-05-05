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

    # アルゴリズム: 軌跡上の最近接点インデックスでソートする方式。
    #
    # 1. 路線の bus_route_tracks を「並行軌跡スキップ + 端点連結」で 1 本の座標列に繋ぎ合わせる。
    # 2. 各 bus_route_bus_stop について、その停留所と最も近い軌跡座標のインデックスを計算。
    # 3. インデックス昇順 + bus_route_bus_stop.id を tie-break として安定ソート。
    # 4. 並べた順に 1, 2, 3, ... と番号を振る。
    #
    # 連結ロジックの特徴:
    #   - 並行軌跡（head/tail が完全一致する複数 track = 行きと戻りで経路が違うパターン）は
    #     coords 数が多い方を残し、片方をスキップする。これがないと「行き経路の coords + 戻り
    #     経路の coords」が flat 上で混在し、bus_stop の番号付けが「行きと戻りの停留所が交互」
    #     のような逆戻り感のある順序になる。
    #   - 端点同士で繋ぐ貪欲法。Y 字分岐や逆方向 track にも対応するため、head/tail どちらでも
    #     接続を試す（必要なら反転）。
    #   - 同距離なら forward (反転なし) を優先。reversed による逆戻りを防ぐ tie-break。
    stitch_tracks = ->(tracks) {
      pieces = tracks.map { |t|
        coords = t.coordinates
        { id: t.id, coords: coords, head: coords.first, tail: coords.last }
      }.sort_by { |p| p[:id] }

      return [] if pieces.empty?

      # 並行軌跡スキップ: (head, tail) が完全一致する track が複数あるとき、
      # coords 数が多い (= より詳細な軌跡) を残す。tie-break は id で決定論化。
      grouped = pieces.group_by { |p| [ p[:head], p[:tail] ] }
      pieces = grouped.values.map { |dup| dup.max_by { |p| [ p[:coords].size, -p[:id] ] } }
                            .sort_by { |p| p[:id] }

      # 開始: head 経度が最小（同点は id で tie-break）の track。
      start = pieces.min_by { |p| [ p[:head][1], p[:id] ] }
      used = { start[:id] => true }
      flat = start[:coords].dup

      # 末尾に最も近い未使用 track を貪欲に連結。head/tail どちらでも接続できる方を選び、
      # 同距離の場合は forward (反転なし) を優先する。
      while used.size < pieces.size
        current_tail = flat.last
        best_piece = nil
        best_dist = Float::INFINITY
        best_reversed = false
        pieces.each do |p|
          next if used[p[:id]]
          d_head = (current_tail[0] - p[:head][0]) ** 2 + (current_tail[1] - p[:head][1]) ** 2
          d_tail = (current_tail[0] - p[:tail][0]) ** 2 + (current_tail[1] - p[:tail][1]) ** 2
          this_reversed = d_tail < d_head
          d_min = this_reversed ? d_tail : d_head

          if d_min < best_dist || (d_min == best_dist && best_reversed && !this_reversed)
            best_dist = d_min
            best_piece = p
            best_reversed = this_reversed
          end
        end
        break unless best_piece

        coords = best_reversed ? best_piece[:coords].reverse : best_piece[:coords]
        if coords.first == flat.last
          flat.concat(coords[1..])
        else
          flat.concat(coords)
        end
        used[best_piece[:id]] = true
      end

      # 連結できなかった孤立 track (>1km 離れているなど) は経度+id 順で末尾に追加。
      pieces.reject { |p| used[p[:id]] }
            .sort_by { |p| [ p[:head][1], p[:id] ] }
            .each { |p| flat.concat(p[:coords]) }

      flat
    }

    rows = []
    progress = ProgressBar.create(title: "Generate", total: BusRoute.count, format: "%t: %J%% |%B|")

    BusRoute.find_each do |bus_route|
      bus_route_bus_stops = bus_route.bus_route_bus_stops.reorder(:id).includes(:bus_stop).to_a
      flat_coords = stitch_tracks.call(bus_route.bus_route_tracks.to_a)

      if flat_coords.empty?
        bus_route_bus_stops.each { |brbs| rows << [ brbs.id, nil ] }
        progress.increment
        next
      end

      # 各 brbs について軌跡上の最近接点のインデックスを計算する。
      brbs_with_index = bus_route_bus_stops.map do |brbs|
        bs = brbs.bus_stop
        min_idx  = 0
        min_dist = Float::INFINITY
        flat_coords.each_with_index do |c, idx|
          d = (bs.latitude - c[0]) ** 2 + (bs.longitude - c[1]) ** 2
          if d < min_dist
            min_dist = d
            min_idx  = idx
          end
        end
        [ brbs.id, min_idx ]
      end

      brbs_with_index.sort_by! { |id, idx| [ idx, id ] }
      brbs_with_index.each_with_index do |(brbs_id, _), i|
        rows << [ brbs_id, i + 1 ]
      end
      progress.increment
    end

    # bus_route_bus_stop_id 順にソートして CSV に書き出す（diff 比較を安定させるため）。
    rows.sort_by! { |id, _| id }
    CSV.open(csv_path, "w", headers: %w[bus_route_bus_stop_id bus_stop_number], write_headers: true) do |csv|
      rows.each { |row| csv << row }
    end
    puts "Wrote #{csv_path} (#{rows.size} rows)"
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
