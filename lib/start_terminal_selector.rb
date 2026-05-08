# TrackStitcher の起点 (degree-1 endpoint coord) を選ぶ。
#
# 現状の TrackStitcher は「最西端 terminal」固定で起点を決めるが、ループ・8 の字
# 構造を持つ路線では「最西端から始めると greedy が途中で詰まって長距離 bridge
# segment が発生する」ケースが起きる (例: 邑楽町 館林・邑楽・千代田線 4665 では
# 赤岩渡船 起点で 2,632m の bridge が出るが、館林駅 起点なら最大 bridge ~360m)。
#
# 起点選択の優先順:
#   1. line_name の第 1 トークン (例: 「館林・邑楽・千代田線」 → 「館林」) に部分一致する
#      bus_stop を見つけ、最近接 terminal を採用する。距離が HINT_MAX_DISTANCE_M を超えた
#      場合は弱い hint とみなして次へ。
#   2. 半径 STATION_HINT_RADIUS_M 以内に「駅」を含む bus_stop がある terminal を優先採用
#      する。バス路線は鉄道との接続点 (= 駅) を主要 hub にすることが多く、line_name が単一
#      トークン (例: 「温根別線」) で第 1 トークン hint が発火しない路線でも、駅起点に倒す
#      ことで利用者目線の自然な向きになる。
#   3. 各 terminal を起点に TrackStitcher を試行し、bridge segment 距離合計が最小の起点
#      を採用する。
#   4. それでも決まらない (terminal 1 つ以下、純粋循環、両方失敗) → nil を返して
#      TrackStitcher の最西端 fallback に委ねる。
#
# 重要: TrackStitcher の依存を増やさないため、本クラスを通さず TrackStitcher を直接呼んでも
# 現状の最西端 fallback で動く。本クラスはあくまで上位レイヤーで「より良い起点」を選ぶ役割。
class StartTerminalSelector
  EARTH_RADIUS_M = 6_371_000.0

  # line_name 第 1 トークン → 該当 bus_stop の最近接 terminal がこの距離以内なら採用。
  # 1km 以下に絞ると「館林トークン → 館林駅前停留所 → 館林駅 terminal」のように高精度な hint
  # しか採用しない。それ以上離れている場合は line_name と terminal の対応が弱いと判断し、
  # bridge 最小化 fallback に任せる。
  HINT_MAX_DISTANCE_M = 1_000.0

  # terminal の半径この距離以内に「駅」を含む bus_stop があれば駅近 terminal とみなす。
  # 200m に設定: 駅前ロータリーは概ね 100〜150m、少し離れたバス停も拾える距離。これより甘く
  # する (例 500m) と「駅と無関係なバス停が偶然 "駅" を含む地名」を誤って拾うリスクが上がる。
  STATION_HINT_RADIUS_M = 200.0

  def self.call(tracks, line_name: nil, bus_route_bus_stops: nil)
    new(tracks, line_name, bus_route_bus_stops).call
  end

  def initialize(tracks, line_name, bus_route_bus_stops)
    @tracks = tracks
    @line_name = line_name
    @brbs = bus_route_bus_stops
    @terminals = collect_terminals
  end

  def call
    # terminal が 1 つ以下なら TrackStitcher の挙動と一致するので nil を返す。
    return nil if @terminals.size < 2

    if @line_name && @brbs && !@brbs.empty?
      hint = line_name_hint
      return hint if hint
    end

    if @brbs && !@brbs.empty?
      hint = station_hint
      return hint if hint
    end

    multi_try_min_bridge
  end

  private

  # 全 track の head/tail から、出現回数 1 (= 路線の物理終端) のものを集める。
  def collect_terminals
    counts = Hash.new(0)
    @tracks.each do |t|
      coords = t.coordinates
      counts[coords.first] += 1
      counts[coords.last]  += 1
    end
    counts.select { |_, c| c == 1 }.keys
  end

  # line_name 第 1 トークンに部分一致する bus_stop を 1 つ選び、
  # その停留所の最近接 terminal を返す (距離 ≤ HINT_MAX_DISTANCE_M なら)。
  def line_name_hint
    tokens = LineNameOrienter.parse_tokens(@line_name)
    return nil if tokens.empty?

    first_tok = tokens.first
    matched = @brbs.find { |b| b.bus_stop.name.include?(first_tok) }
    return nil unless matched

    bs = matched.bus_stop
    closest, dist = nearest_terminal(bs.latitude, bs.longitude)
    dist <= HINT_MAX_DISTANCE_M ? closest : nil
  end

  # 「駅」を名前に含む bus_stop が STATION_HINT_RADIUS_M 以内にある terminal を優先する。
  # 複数の terminal が条件を満たす場合は、駅停留所との距離が最小のものを採用 (大都市圏で
  # 両端 terminal が駅近のときは「より駅前らしい方」が選ばれる)。
  def station_hint
    station_stops = @brbs.select { |b| b.bus_stop.name.include?("駅") }
    return nil if station_stops.empty?

    best_terminal = nil
    best_dist = Float::INFINITY
    @terminals.each do |coord|
      station_stops.each do |b|
        d = haversine(coord[0], coord[1], b.bus_stop.latitude, b.bus_stop.longitude)
        if d < best_dist
          best_dist = d
          best_terminal = coord
        end
      end
    end

    best_dist <= STATION_HINT_RADIUS_M ? best_terminal : nil
  end

  # 各 terminal を起点に stitcher を回し、bridge segment の距離合計が最小の起点を返す。
  # tiebreak は最西端 (現状互換)。
  def multi_try_min_bridge
    scored = @terminals.map do |coord|
      result = TrackStitcher.call_with_diagnostics(@tracks, start: coord)
      total = result.bridge_segment_indices.sum { |i|
        next 0.0 if i + 1 >= result.flat_coords.size
        a = result.flat_coords[i]
        b = result.flat_coords[i + 1]
        haversine(a[0], a[1], b[0], b[1])
      }
      [ coord, total ]
    end
    scored.min_by { |coord, total| [ total, coord[1], coord[0] ] }&.first
  end

  def nearest_terminal(lat, lng)
    best_coord = nil
    best_dist = Float::INFINITY
    @terminals.each do |coord|
      d = haversine(coord[0], coord[1], lat, lng)
      if d < best_dist
        best_dist = d
        best_coord = coord
      end
    end
    [ best_coord, best_dist ]
  end

  def haversine(lat1, lng1, lat2, lng2)
    rad = Math::PI / 180.0
    dlat = (lat2 - lat1) * rad
    dlng = (lng2 - lng1) * rad
    a = Math.sin(dlat / 2.0) ** 2 +
        Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dlng / 2.0) ** 2
    2.0 * EARTH_RADIUS_M * Math.asin(Math.sqrt(a))
  end
end
