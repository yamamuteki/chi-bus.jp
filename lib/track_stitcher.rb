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
#   - **Leaf spur 挿入**: greedy が junction (端点重複度 3+) に到達した時点で、その junction から
#     生える「他端が degree 1 = 終端」の枝 (= leaf spur) があれば、greedy で先に進む前に
#     spur を取り込む。spur は coords 数が小さい方から処理する (= 短い枝を side branch とみなす)。
#     これがないと、junction の片側を greedy が先に進んでしまい、後で spur に戻るために
#     大ジャンプ (例: 5885 で 5752m) が発生していた。
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
    :bridge_segment_indices,
    keyword_init: true
  )

  # 連結履歴の 1 ステップ。inspect task の目視デバッグで使う。
  StitchStep = Struct.new(:track_id, :reversed, :join_distance, :coords_size, :isolated, keyword_init: true)

  # 連結ジャンプとして警告対象にする閾値 (m)。
  # 連続 coord 間でこれ以上飛んでいたら「track の連結部に不連続がある」サインとみなす。
  LARGE_JUMP_THRESHOLD_M = 100.0

  # leaf spur 挿入の最大長さ (m, 端点間直線距離)。これより長い spur は「本線の一部」
  # の可能性が高いので spur 挿入対象外とし、通常の greedy に任せる。
  # 例: 旭市 飯岡 (58) の track #174 は 4.3km の主要セグメントだが head/tail が
  # たまたま degree 3 / degree 1 の関係で「leaf spur」判定になる。挿入してしまうと
  # 戻るのに 4km 級のジャンプが発生し採番が崩れる。500m は典型的なバス停間距離の
  # 数倍 = 「side branch にしては長過ぎる」を区別する目安。
  SPUR_MAX_LENGTH_M = 500.0

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
        stitch_steps: [],
        bridge_segment_indices: []
      )
    end

    # 並行軌跡の処理: (head, tail) が完全一致する track が複数あるとき、
    #   - **coords array が完全一致** → 真の重複 (XML 由来の同一データ)。1 本だけ残す。
    #   - **coords array が異なる** → 行き帰りで別経路の並行軌跡。両方残すが、
    #     パートナー (= primary 以外) を `alternate_ids` に登録して greedy の outbound phase
    #     では使わせない。outbound 完了 (= 全 primary 利用済み or 接続不能) 後に return phase
    #     で利用する。これにより「outbound で primary を辿って終端到達 → return で alternate
    #     を辿って戻る」という往復モデルが自然に実現する。
    # ※ UI 側 (application_helper.rb#build_routes) は全 bus_route_tracks を polyline 描画する
    #    ため、stitcher で片方を捨てると「polyline は両経路、採番は片経路のみ」のミスマッチが
    #    生じる (例: 坂東市 5985)。両経路を残すことで整合させる。
    grouped = pieces.group_by { |p| [ p[:head], p[:tail] ] }
    alternate_ids = {}  # Hash で fast lookup
    pieces = grouped.values.flat_map do |dup|
      if dup.size == 1
        dup
      elsif dup.map { |p| p[:coords] }.uniq.size == 1
        # 全 member の coords が完全一致 → 真の重複。id 最小を残す。
        [ dup.max_by { |p| -p[:id] } ]
      elsif haversine_meters(dup.first[:head][0], dup.first[:head][1],
                             dup.first[:tail][0], dup.first[:tail][1]) <= SPUR_MAX_LENGTH_M
        # head/tail が一致するが coords 数が違う + 端点間距離が短い (≤500m) →
        # 解像度違いで描かれた同一の短セグメント。並行軌跡 (= 行き帰りで別ルート) なら
        # endpoint 間距離は普通 km オーダーになるので、500m 以下の「並行軌跡」は地理的に
        # ありえないケースがほとんど。alternate に回すと return phase で長距離ジャンプを
        # 引き起こすので (玉野渋川特急線 20585: 19km の bridge segment が発生し、numberer が
        # 玉野営業所前を岡山駅の後ろに置いた)、coords 数最大を残して残りは捨てる。
        [ dup.max_by { |p| [ p[:coords].size, -p[:id] ] } ]
      else
        # coords が異なる → 行き帰り別経路。primary (coords 多い方、tie は id 若い方)
        # と alternate (残り) に分ける。alternate は outbound phase で除外、return phase で使う。
        sorted = dup.sort_by { |p| [ -p[:coords].size, p[:id] ] }
        sorted[1..].each { |p| alternate_ids[p[:id]] = true }
        sorted
      end
    end.sort_by { |p| p[:id] }
    skipped_parallel = total - pieces.size

    # 端点重複度の集計。各端点が何個の track に共有されているかを数える。
    # 「重複度 1」の端点 = 路線の物理的終端 (バス車庫・終点バス停など) と推定。
    # 終端起点の方が「Y 字の枝に迷い込んで戻れない」ケースを減らせる。
    endpoint_counts = Hash.new(0)
    pieces.each do |p|
      endpoint_counts[p[:head]] += 1
      endpoint_counts[p[:tail]] += 1
    end

    # 起点選択の優先順:
    #   (1) 全 piece の両端を走査し、重複度 1 (= 終端) の端点の中で最も西の経度を起点に。
    #   (2) 該当なし (純粋循環) → 各 piece の westmost 端点の中で最西を起点に fallback。
    #
    # PR #50 は各 piece の west_end のみを終端候補としていたため、終端が piece の
    # east 側にある場合 (例: 横浜浅83 の 12160 tail at lng 139.5751、head は 139.5742)
    # を見逃していた。両端を独立に評価することで対応する。
    # 注意: alternate は head/tail を primary と共有するため degree 1 端点を持たない
    # (= terminal にならない)。fallback も primary のみで回す (alternate を起点にしても
    # 構造上 outbound として意味が薄い)。
    terminal_starts = []
    pieces.each do |p|
      next if alternate_ids[p[:id]]
      terminal_starts << { piece: p, lng: p[:head][1], reversed: false } if endpoint_counts[p[:head]] == 1
      terminal_starts << { piece: p, lng: p[:tail][1], reversed: true } if endpoint_counts[p[:tail]] == 1
    end

    start_meta = if !terminal_starts.empty?
      terminal_starts.min_by { |m| [ m[:lng], m[:piece][:id] ] }
    else
      # 終端が無い (= 純粋循環) 場合のみ、各 piece の westmost 端点を候補に最西選定。
      pieces.reject { |p| alternate_ids[p[:id]] }.map { |p|
        west_is_tail = p[:tail][1] < p[:head][1]
        west_lng = west_is_tail ? p[:tail][1] : p[:head][1]
        { piece: p, lng: west_lng, reversed: west_is_tail }
      }.min_by { |m| [ m[:lng], m[:piece][:id] ] }
    end

    start = start_meta[:piece]
    start_reversed = start_meta[:reversed]
    used = { start[:id] => true }
    flat = start_reversed ? start[:coords].reverse : start[:coords].dup
    reversed_count = start_reversed ? 1 : 0
    connection_jumps = []
    stitch_steps = [ StitchStep.new(track_id: start[:id], reversed: start_reversed, join_distance: 0.0, coords_size: start[:coords].size, isolated: false) ]
    # flat_coords 上で「stitcher が track 間を強引に繋いだ」virtual segment の index を記録する。
    # 後段の BusStopNumberer がこれを skip することで、軌跡上に存在しない直線 (例: 19km の bridge)
    # にバス停が誤って射影されるのを防ぐ。
    bridge_segment_indices = []

    # Leaf spur 挿入: 現 flat.last が junction (重複度 3+) で、未使用の leaf spur がある間 take。
    # 短い枝 (coords 少ない) → side branch として先に処理。長い枝 (本線続き) は greedy に任せる。
    # 取得後、新 flat.last は spur の terminal (重複度 1) なので junction 条件で自然に break。
    insert_spur = -> {
      loop do
        break if (endpoint_counts[flat.last] || 0) < 3

        spur_candidates = []
        pieces.each do |p|
          next if used[p[:id]]
          if p[:head] == flat.last
            other = p[:tail]
          elsif p[:tail] == flat.last
            other = p[:head]
          else
            next
          end
          next unless endpoint_counts[other] == 1
          # 端点間直線距離が SPUR_MAX_LENGTH_M を超える track は本線の一部と推定し
          # spur 挿入の対象外とする (= 通常 greedy で扱う)。
          spur_length = haversine_meters(p[:head][0], p[:head][1], p[:tail][0], p[:tail][1])
          next if spur_length > SPUR_MAX_LENGTH_M
          spur_candidates << p
        end
        break if spur_candidates.empty?

        spur = spur_candidates.min_by { |p| [ p[:coords].size, p[:id] ] }
        spur_reversed = (spur[:tail] == flat.last)

        coords = spur_reversed ? spur[:coords].reverse : spur[:coords]
        reversed_count += 1 if spur_reversed

        join_dist = haversine_meters(flat.last[0], flat.last[1], coords.first[0], coords.first[1])
        connection_jumps << join_dist
        stitch_steps << StitchStep.new(
          track_id: spur[:id],
          reversed: spur_reversed,
          join_distance: join_dist,
          coords_size: spur[:coords].size,
          isolated: false
        )

        if coords.first == flat.last
          flat.concat(coords[1..])
        else
          bridge_segment_indices << flat.size - 1
          flat.concat(coords)
        end
        used[spur[:id]] = true
      end
    }

    # 起点直後にも spur 挿入を試行 (起点が junction で終わっている場合)。
    insert_spur.call

    # 末尾に最も近い未使用 track を貪欲に連結。head/tail どちらでも接続できる方を選び、
    # 同距離の場合は forward (反転なし) を優先する。
    # phase = :outbound では alternate を除外、:return では alternate を含めて連結する。
    # outbound で連結不能になった (= primary 全消化 or 全 alternate しか残らない) 段階で
    # phase を :return に切り替えて続行する。
    phase = :outbound
    while used.size < pieces.size
      current_tail = flat.last
      best_piece = nil
      best_dist = Float::INFINITY
      best_reversed = false
      pieces.each do |p|
        next if used[p[:id]]
        next if phase == :outbound && alternate_ids[p[:id]]
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

      if best_piece.nil?
        if phase == :outbound && alternate_ids.any?
          phase = :return
          next
        else
          break
        end
      end

      coords = best_reversed ? best_piece[:coords].reverse : best_piece[:coords]
      reversed_count += 1 if best_reversed

      # 連結部の距離を記録 (重複点除去前に測定)。
      join_dist = haversine_meters(flat.last[0], flat.last[1], coords.first[0], coords.first[1])
      connection_jumps << join_dist
      stitch_steps << StitchStep.new(track_id: best_piece[:id], reversed: best_reversed, join_distance: join_dist, coords_size: coords.size, isolated: false)

      if coords.first == flat.last
        flat.concat(coords[1..])
      else
        bridge_segment_indices << flat.size - 1
        flat.concat(coords)
      end
      used[best_piece[:id]] = true

      # 各 greedy ステップの後に spur 挿入を試行。
      insert_spur.call
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
      bridge_segment_indices << flat.size - 1
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
      stitch_steps: stitch_steps,
      bridge_segment_indices: bridge_segment_indices
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
