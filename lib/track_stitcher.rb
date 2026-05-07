# 路線の複数 BusRouteTrack を 1 本の coord 列に連結する。
#
# bus_stop_number 採番のための前処理。各バス停を「軌跡上の 1D 位置」に対応付けたい
# ので、複数 track を順序のある単一の座標列に直列化する役割を担う。
#
# 連結ロジックの特徴:
#   - 並行軌跡 (head/tail が完全一致する複数 track = 行きと戻りで経路が違うパターン)
#     は coords 数が多い方を残し、片方をスキップする。これがないと「行き経路の coords
#     + 戻り経路の coords」が flat 上で混在し、bus_stop の番号付けが「行きと戻りの停留所
#     が交互」のような逆戻り感のある順序になる。
#   - 端点同士で繋ぐ貪欲法。Y 字分岐や逆方向 track にも対応するため、head/tail どちらでも
#     接続を試す（必要なら反転）。
#   - 同距離なら forward (反転なし) を優先。reversed による逆戻りを防ぐ tie-break。
#
# 診断用に call_with_diagnostics を提供。stitch の品質を測る指標を返す。
#   - max_jump_distance: 全連続点間 (track 内 + 連結部) の最大ジャンプ距離
#   - connection_jump_max: 連結部のみの最大ジャンプ距離
#     (= 「stitch が track A の末尾と track B の頭を強引に繋いだときの跳躍」)
#   - track 内ジャンプは N07 の coord 解像度起因なので stitch の責任外。
#     connection_jump_max が大きければ stitch の連結が破綻しているサイン。
class TrackStitcher
  Result = Struct.new(
    :flat_coords,
    :total_tracks,
    :skipped_parallel,
    :reversed_count,
    :isolated_count,
    :max_jump_distance,
    :large_jump_count,
    :connection_jump_max,
    :connection_large_jump_count,
    :connection_count,
    :stitch_steps,
    keyword_init: true
  )

  # 連結履歴の 1 ステップ。inspect task の目視デバッグで使う。
  StitchStep = Struct.new(:track_id, :reversed, :join_distance, :coords_size, :isolated, keyword_init: true)

  # 連結ジャンプとして警告対象にする閾値 (m)。
  # 連続 coord 間でこれ以上飛んでいたら「track の連結部に不連続がある」サインとみなす。
  LARGE_JUMP_THRESHOLD_M = 100.0

  def self.call(tracks)
    new(tracks).run.flat_coords
  end

  def self.call_with_diagnostics(tracks)
    new(tracks).run
  end

  def initialize(tracks)
    @tracks = tracks
  end

  def run
    total = @tracks.size
    pieces = @tracks.map { |t|
      coords = t.coordinates
      { id: t.id, coords: coords, head: coords.first, tail: coords.last }
    }.sort_by { |p| p[:id] }

    if pieces.empty?
      return Result.new(
        flat_coords: [],
        total_tracks: 0,
        skipped_parallel: 0,
        reversed_count: 0,
        isolated_count: 0,
        max_jump_distance: 0.0,
        large_jump_count: 0,
        connection_jump_max: 0.0,
        connection_large_jump_count: 0,
        connection_count: 0,
        stitch_steps: []
      )
    end

    # 並行軌跡スキップ: (head, tail) が完全一致する track が複数あるとき、
    # coords 数が多い (= より詳細な軌跡) を残す。tie-break は id で決定論化。
    grouped = pieces.group_by { |p| [ p[:head], p[:tail] ] }
    pieces = grouped.values.map { |dup| dup.max_by { |p| [ p[:coords].size, -p[:id] ] } }
                          .sort_by { |p| p[:id] }
    skipped_parallel = total - pieces.size

    # 開始候補の生成: 各 piece について「両端のうち西側に近い側」を起点に使う meta。
    # 旧実装は head 経度だけ見ていたため、coord 順が「東→西」の track が選ばれた場合に
    # 反転されず、flat の前半が逆走 → 後段で大きな U ターンジャンプを生んでいた
    # (例: 都01 で渋谷→青学の 1km ジャンプ)。両端を見ることで起点を確実に最西端にし、
    # 必要なら反転して flat を一貫した方向で組み立てる。
    start_metas = pieces.map { |p|
      west_is_tail = p[:tail][1] < p[:head][1]
      west_end = west_is_tail ? p[:tail] : p[:head]
      { piece: p, west_end: west_end, west_lng: west_end[1], reversed: west_is_tail }
    }

    # 端点重複度の集計。各端点が何個の track に共有されているかを数える。
    # 「重複度 1」の端点 = 路線の物理的終端 (バス車庫・終点バス停など) と推定。
    # 終端起点の方が「Y 字の枝に迷い込んで戻れない」ケースを減らせる。
    endpoint_counts = Hash.new(0)
    pieces.each do |p|
      endpoint_counts[p[:head]] += 1
      endpoint_counts[p[:tail]] += 1
    end

    # 起点選択の優先順:
    #   (1) 西側端点が重複度 1 (= 終端) で、かつ最も西の経度
    #   (2) 該当なし → 従来通り最西端 (= 重複度を問わず最も西の端点)
    # min_by の sort_key を「重複度 1 を優先するため 0/1 prefix」で表現。
    start_meta = start_metas.min_by { |m|
      [ endpoint_counts[m[:west_end]] == 1 ? 0 : 1, m[:west_lng], m[:piece][:id] ]
    }

    start = start_meta[:piece]
    start_reversed = start_meta[:reversed]
    used = { start[:id] => true }
    flat = start_reversed ? start[:coords].reverse : start[:coords].dup
    reversed_count = start_reversed ? 1 : 0
    connection_jumps = []
    stitch_steps = [ StitchStep.new(track_id: start[:id], reversed: start_reversed, join_distance: 0.0, coords_size: start[:coords].size, isolated: false) ]

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
      reversed_count += 1 if best_reversed

      # 連結部の距離を記録 (重複点除去前に測定)。
      join_dist = haversine_meters(flat.last[0], flat.last[1], coords.first[0], coords.first[1])
      connection_jumps << join_dist
      stitch_steps << StitchStep.new(track_id: best_piece[:id], reversed: best_reversed, join_distance: join_dist, coords_size: coords.size, isolated: false)

      if coords.first == flat.last
        flat.concat(coords[1..])
      else
        flat.concat(coords)
      end
      used[best_piece[:id]] = true
    end

    # 連結できなかった孤立 track は経度+id 順で末尾に追加。
    # 現状ロジックでは距離上限を持たない貪欲法のため発生しないはずだが、
    # 念のため発生したらカウントしておく。
    isolated = pieces.reject { |p| used[p[:id]] }
                     .sort_by { |p| [ p[:head][1], p[:id] ] }
    isolated.each do |p|
      join_dist = haversine_meters(flat.last[0], flat.last[1], p[:coords].first[0], p[:coords].first[1])
      connection_jumps << join_dist
      stitch_steps << StitchStep.new(track_id: p[:id], reversed: false, join_distance: join_dist, coords_size: p[:coords].size, isolated: true)
      flat.concat(p[:coords])
    end

    # 連続点間の最大ジャンプ (track 内 + 連結部 が混ざった指標)。
    max_jump = 0.0
    large_jump_count = 0
    flat.each_cons(2) do |a, b|
      dist = haversine_meters(a[0], a[1], b[0], b[1])
      max_jump = dist if dist > max_jump
      large_jump_count += 1 if dist > LARGE_JUMP_THRESHOLD_M
    end

    Result.new(
      flat_coords: flat,
      total_tracks: total,
      skipped_parallel: skipped_parallel,
      reversed_count: reversed_count,
      isolated_count: isolated.size,
      max_jump_distance: max_jump,
      large_jump_count: large_jump_count,
      connection_jump_max: connection_jumps.max || 0.0,
      connection_large_jump_count: connection_jumps.count { |d| d > LARGE_JUMP_THRESHOLD_M },
      connection_count: connection_jumps.size,
      stitch_steps: stitch_steps
    )
  end

  private

  EARTH_RADIUS_M = 6_371_000.0

  def haversine_meters(lat1, lng1, lat2, lng2)
    rad = Math::PI / 180.0
    dlat = (lat2 - lat1) * rad
    dlng = (lng2 - lng1) * rad
    a = Math.sin(dlat / 2.0) ** 2 +
        Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dlng / 2.0) ** 2
    2.0 * EARTH_RADIUS_M * Math.asin(Math.sqrt(a))
  end
end
