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
class BusStopNumberer
  def self.call(flat_coords:, bus_route_bus_stops:)
    new(flat_coords, bus_route_bus_stops).call
  end

  def initialize(flat_coords, bus_route_bus_stops)
    @flat_coords = flat_coords
    @brbs = bus_route_bus_stops
  end

  def call
    if @flat_coords.empty?
      return @brbs.map { |b| [ b.id, nil ] }
    end

    # flat_coords が 1 点しかない場合は segment が作れない。全 brbs を idx=0 の点との距離で並べる。
    if @flat_coords.size == 1
      c = @flat_coords[0]
      result = @brbs.map { |brbs|
        bs = brbs.bus_stop
        d = (bs.latitude - c[0]) ** 2 + (bs.longitude - c[1]) ** 2
        [ brbs.id, 0.0, d ]
      }
      result.sort_by! { |id, pos, dist| [ pos, dist, id ] }
      return result.each_with_index.map { |(id, _, _), i| [ id, i + 1 ] }
    end

    # 各 brbs について、最も近い segment と segment 内位置 t を計算して
    # curvilinear position (= segment_index + t) を求める。
    result = @brbs.map do |brbs|
      bs = brbs.bus_stop
      lat = bs.latitude
      lng = bs.longitude

      best_segment = 0
      best_t = 0.0
      best_dist_sq = Float::INFINITY

      @flat_coords.each_cons(2).with_index do |(p, q), i|
        dx = q[0] - p[0]
        dy = q[1] - p[1]
        seg_len_sq = dx * dx + dy * dy

        if seg_len_sq < 1e-15
          # 退化セグメント (p == q): 端点を採用。
          t = 0.0
          cx = p[0]
          cy = p[1]
        else
          # 線分上への射影。t を [0, 1] にクランプして外挿を防ぐ (この segment の範囲外は
          # 隣接 segment が拾う想定)。
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

      [ brbs.id, best_segment + best_t, best_dist_sq ]
    end

    # curvilinear position 昇順 → 同位置は距離順 → 同距離は id 順で安定化。
    result.sort_by! { |id, pos, dist| [ pos, dist, id ] }
    result.each_with_index.map { |(id, _, _), i| [ id, i + 1 ] }
  end
end
