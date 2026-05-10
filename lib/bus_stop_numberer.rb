# 路線内のバス停に bus_stop_number (1 始まりの順序) を割り当てる。
#
# TrackStitcher が組み立てた flat_coords (1D 化された座標列) と、bus_route_bus_stops の集合を
# 受け取って、各 brbs に「軌跡上での順序」を付ける。
#
# アルゴリズム: segment + t (curvilinear position) 方式。
#   - 各バス停について flat の全 segment (flat[i], flat[i+1]) で「直線への垂線の足」を計算し、
#     最も近い segment を選んで segment 番号 i と segment 内位置 t (0〜1) を求める。
#   - ソートキーは (i + t)。これで coord 解像度が粗くても順序が安定する。
#   - 旧方式 (coord idx ベース最近接) との違い: SimplifyRb で coord 列が間引かれ、coord 間隔が
#     100m 以上ある区間では複数バス停が同 idx に吸い込まれて tie-break (距離) で並ぶことがあり、
#     軌跡進行方向と逆順になるケースがあった (例: 都営南千47 の 泪橋/清川)。
#     segment + t なら 1 つの coord 間にあるバス停同士でも進行順に並ぶ。
#
# 診断用に call_with_diagnostics を提供。各バス停の軌跡からの距離 (m) を一緒に返す。
# 距離が大きいバス停は「軌跡データが路線をカバーしていない」サインで、データ欠損を識別できる
# (例: 神奈川中央交通 津01 で 32 バス停が軌跡から 20km 離れている)。
class BusStopNumberer
  # vertex_indices: pick_best_assignment の count_inversions / diagnose の idx_inversions が使う
  # 「各 brbs の最近接 vertex の flat_coords 内 index」。numberer 本体の射影ループに乗せて
  # 1 回の iteration で計算するので、後段の inversion チェックは flat_coords を再走査せずに済む。
  # bridge segment は (count_inversions と挙動を揃えるため) フィルタしない。
  Result = Struct.new(:assignments, :distances_m, :vertex_indices, keyword_init: true)

  # 緯度 1 度 ≈ 111km の近似で度² から m に変換する係数。
  # (経度方向は緯度依存だが、200m 閾値の判定なら近似で十分。)
  DEG_TO_M = 111_000.0

  def self.call(flat_coords:, bus_route_bus_stops:, bridge_segment_indices: [])
    new(flat_coords, bus_route_bus_stops, bridge_segment_indices).call_with_diagnostics.assignments
  end

  def self.call_with_diagnostics(flat_coords:, bus_route_bus_stops:, bridge_segment_indices: [])
    new(flat_coords, bus_route_bus_stops, bridge_segment_indices).call_with_diagnostics
  end

  def initialize(flat_coords, bus_route_bus_stops, bridge_segment_indices = [])
    @flat_coords = flat_coords
    @brbs = bus_route_bus_stops
    # TrackStitcher が track 間を強引に繋いだ virtual segment の index 集合。射影対象から除外する。
    # これがないと、19km 級の bridge segment 上に偶然乗る位置にあるバス停 (例: 玉野渋川特急線
    # 20585 の 玉野営業所前) が、本来の位置ではなく flat 末尾に近い高い curvilinear position に
    # 押し出される (segment index 137 + t=0.978 → 路線終点扱い)。
    @bridge_segments = bridge_segment_indices.to_set
  end

  def call_with_diagnostics
    if @flat_coords.empty?
      assignments = @brbs.map { |b| [ b.id, nil ] }
      distances = @brbs.to_h { |b| [ b.id, nil ] }
      vertex_indices = @brbs.to_h { |b| [ b.id, nil ] }
      return Result.new(assignments: assignments, distances_m: distances, vertex_indices: vertex_indices)
    end

    # flat_coords が 1 点しかない場合は segment が作れない。全 brbs を idx=0 の点との距離で並べる。
    if @flat_coords.size == 1
      c = @flat_coords[0]
      pre = @brbs.map { |brbs|
        bs = brbs.bus_stop
        d = (bs.latitude - c[0]) ** 2 + (bs.longitude - c[1]) ** 2
        [ brbs.id, 0.0, d ]
      }
      sorted = pre.sort_by { |id, pos, dist_sq| [ pos, dist_sq, id ] }
      assignments = sorted.each_with_index.map { |(id, _, _), i| [ id, i + 1 ] }
      distances = pre.to_h { |id, _, dist_sq| [ id, Math.sqrt(dist_sq) * DEG_TO_M ] }
      vertex_indices = @brbs.to_h { |b| [ b.id, 0 ] }
      return Result.new(assignments: assignments, distances_m: distances, vertex_indices: vertex_indices)
    end

    last_idx = @flat_coords.size - 1
    last_c = @flat_coords[last_idx]

    # 各 brbs について、最も近い segment と segment 内位置 t (採番用) と、
    # 最も近い vertex の index (inversion チェック用) を 1 ループで計算する。
    pre = @brbs.map do |brbs|
      bs = brbs.bus_stop
      lat = bs.latitude
      lng = bs.longitude

      best_segment = 0
      best_t = 0.0
      best_dist_sq = Float::INFINITY

      # vertex 距離は count_inversions の挙動と揃えるため bridge segment フィルタを適用しない。
      best_vertex_idx = 0
      best_vertex_dist_sq = Float::INFINITY

      @flat_coords.each_cons(2).with_index do |(p, q), i|
        # vertex 距離 (segment 始点 p のみここで見る。終点 q はループ外で last_idx を 1 回確認)。
        dvp = (lat - p[0]) ** 2 + (lng - p[1]) ** 2
        if dvp < best_vertex_dist_sq
          best_vertex_dist_sq = dvp
          best_vertex_idx = i
        end

        next if @bridge_segments.include?(i)
        dx = q[0] - p[0]
        dy = q[1] - p[1]
        seg_len_sq = dx * dx + dy * dy

        if seg_len_sq < 1e-15
          # 退化セグメント (p == q): 端点を採用。
          t = 0.0
          cx = p[0]
          cy = p[1]
        else
          # 線分上への射影。t を [0, 1] にクランプして外挿を防ぐ。
          t = ((lat - p[0]) * dx + (lng - p[1]) * dy) / seg_len_sq
          t = 0.0 if t < 0.0
          t = 1.0 if t > 1.0
          cx = p[0] + t * dx
          cy = p[1] + t * dy
        end

        d = (lat - cx) ** 2 + (lng - cy) ** 2
        if d < best_dist_sq
          best_dist_sq = d
          best_segment = i
          best_t = t
        end
      end

      # 最終 vertex (= flat_coords[last_idx]) はループ内では p として現れないので、ここで 1 回確認。
      d_last = (lat - last_c[0]) ** 2 + (lng - last_c[1]) ** 2
      if d_last < best_vertex_dist_sq
        best_vertex_idx = last_idx
      end

      [ brbs.id, best_segment + best_t, best_dist_sq, best_vertex_idx ]
    end

    # curvilinear position 昇順 → 同位置は距離順 → 同距離は id 順で安定化。
    sorted = pre.sort_by { |id, pos, dist_sq, _vidx| [ pos, dist_sq, id ] }
    assignments = sorted.each_with_index.map { |(id, _, _, _), i| [ id, i + 1 ] }
    distances = pre.to_h { |id, _, dist_sq, _vidx| [ id, Math.sqrt(dist_sq) * DEG_TO_M ] }
    vertex_indices = pre.to_h { |id, _, _, vidx| [ id, vidx ] }
    Result.new(assignments: assignments, distances_m: distances, vertex_indices: vertex_indices)
  end
end
