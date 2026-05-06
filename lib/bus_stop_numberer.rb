# 路線内のバス停に bus_stop_number (1 始まりの順序) を割り当てる。
#
# TrackStitcher が組み立てた flat_coords (1D 化された座標列) と、bus_route_bus_stops の集合を
# 受け取って、各 brbs に「軌跡上での順序」を付ける。
#
# アルゴリズム: sweep (進行順) 方式。
#   - 各バス停について flat_coords を頭から走査し、距離が「最初の局所最小」を取った idx で
#     確定する (距離が閾値以下のもののみ)。一度確定したバス停はそれ以降を見ない。
#   - 旧方式 (flat 全体の単純最近接 idx) との違い: 循環路線で同じ場所を 2 回通る場合、
#     2 回目の通過で順序がねじれず、1 回目の進行に従って採番される。
#   - 軌跡から閾値以上離れたバス停は sweep で確定できないので、最後に flat 全体での最近接 idx で
#     末尾に追加する (旧方式と同じフォールバック)。
#
# 閾値: SWEEP_THRESHOLD_M = 100m。N07 軌跡 (道路中心線) からのバス停の通常距離 (10〜30m) と、
# バス停間隔の最小 (約 200m) の中間。100m 以内であれば「軌跡がそのバス停を通過した」と
# みなしてよい。これより遠いバス停を sweep で「最初の局所最小」で確定すると、並走路線の
# 交差点付近などで誤確定するため、フォールバック側で扱う。
class BusStopNumberer
  SWEEP_THRESHOLD_M = 100.0
  # 緯度 1 度 ≈ 111km、経度は緯度依存だが東京付近で 1 度 ≈ 91km。
  # squared euclidean (lat,lng) で比較するため緯度を採用 (より厳しめ)。
  SWEEP_THRESHOLD_DEG_SQ = (SWEEP_THRESHOLD_M / 111_000.0) ** 2

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

    result = []

    @brbs.each do |brbs|
      bs = brbs.bus_stop
      lat = bs.latitude
      lng = bs.longitude

      prev_dist = Float::INFINITY
      approach_idx = 0
      found = false

      @flat_coords.each_with_index do |c, idx|
        d = (lat - c[0]) ** 2 + (lng - c[1]) ** 2

        if d <= prev_dist
          # まだ近づいている (タイも更新側に倒す)。
          prev_dist = d
          approach_idx = idx
        elsif prev_dist < SWEEP_THRESHOLD_DEG_SQ
          # 増加に転じた + 閾値内 → 確定。
          result << [ brbs.id, approach_idx, prev_dist ]
          found = true
          break
        end
        # 増加だが閾値外: prev_dist を保ったまま続行。後でもう一度近づけば再判定可能。
      end

      next if found

      # 走査終了時に未確定: 残った prev_dist (= flat 全体での最小値) で末尾追加。
      result << [ brbs.id, approach_idx, prev_dist ]
    end

    # idx 昇順 → 同 idx は距離順 → 同距離は id 順で安定化。
    result.sort_by! { |id, idx, dist| [ idx, dist, id ] }
    result.each_with_index.map { |(id, _, _), i| [ id, i + 1 ] }
  end
end
