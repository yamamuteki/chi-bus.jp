require "test_helper"

# DB を使わない PORO の単体テスト。
class StartTerminalSelectorTest < Minitest::Test
  TrackDouble = Struct.new(:id, :coordinates, keyword_init: true)
  BrbsDouble = Struct.new(:id, :bus_stop, keyword_init: true)
  StopDouble = Struct.new(:name, :latitude, :longitude, keyword_init: true)

  def t(id, coords)
    TrackDouble.new(id: id, coordinates: coords)
  end

  def brbs(id, name, lat, lng)
    BrbsDouble.new(id: id, bus_stop: StopDouble.new(name: name, latitude: lat, longitude: lng))
  end

  def test_returns_nil_when_no_terminals
    # 純粋循環 (全 endpoint が degree 2 以上) → nil → TrackStitcher の最西端 fallback に委ねる。
    a = t(1, [ [ 35.0, 140.0 ], [ 35.1, 140.0 ] ])
    b = t(2, [ [ 35.1, 140.0 ], [ 35.05, 140.05 ] ])
    c = t(3, [ [ 35.05, 140.05 ], [ 35.0, 140.0 ] ])
    assert_nil StartTerminalSelector.call([ a, b, c ])
  end

  def test_returns_nil_when_only_one_terminal
    # terminal が 1 つ (= 単純な行き止まり) → 選択肢なし → nil。
    a = t(1, [ [ 35.0, 140.0 ], [ 35.1, 140.0 ] ])  # 35.0,140.0 が degree 1
    b = t(2, [ [ 35.1, 140.0 ], [ 35.0, 140.05 ] ])
    c = t(3, [ [ 35.0, 140.05 ], [ 35.1, 140.0 ] ])
    # 35.0,140.0 が唯一の degree-1 endpoint
    assert_nil StartTerminalSelector.call([ a, b, c ])
  end

  def test_picks_terminal_minimizing_bridge_total
    # 8 の字: 北から東に伸びる leg と、北からループして南へ戻る leg。
    # 西端 leaf 起点だと bridge が大きい。東端 leaf 起点だと bridge が最小化される。
    # ここでは単純化版: a-b で「西端 → mid」、c-d で「東端 → mid → 西端ループ」のような構造。
    # 西端 (35.0,140.0) と 東端 (35.0,140.3) が degree 1 terminal。
    # 中央 junction (35.0,140.1) は degree 3。
    # west leaf 起点: westward greedy で長距離 bridge 発生
    # east leaf 起点: 自然に進むので bridge 最小
    #
    # ここでは多 try が「複数 terminal を試して bridge 最小を選ぶ」挙動を持つことを確認する
    # 簡易ケース。詳細な構造再現は本物の路線データで検証 (4665 等)。
    a = t(1, [ [ 35.0, 140.0 ], [ 35.0, 140.1 ] ])  # 西 leg
    b = t(2, [ [ 35.0, 140.1 ], [ 35.0, 140.2 ] ])  # 中央 leg
    c = t(3, [ [ 35.0, 140.2 ], [ 35.0, 140.3 ] ])  # 東 leg
    # この単純な構造では bridge が発生しないので、いずれの起点も同点 → 西端 tiebreak。
    result = StartTerminalSelector.call([ a, b, c ])
    assert_equal [ 35.0, 140.0 ], result
  end

  def test_line_name_hint_picks_matching_terminal
    # line_name 第 1 トークン「鹿島」→ 鹿島駅前 stop (lat 35.0, lng 140.3) → 最近接 terminal
    # は east end (35.0, 140.3)。本来 westmost fallback だと west end (35.0, 140.0) が選ばれるが、
    # line_name hint で east end が選ばれることを確認。
    a = t(1, [ [ 35.0, 140.0 ], [ 35.0, 140.1 ] ])
    b = t(2, [ [ 35.0, 140.1 ], [ 35.0, 140.2 ] ])
    c = t(3, [ [ 35.0, 140.2 ], [ 35.0, 140.3 ] ])
    stops = [
      brbs(1, "西の駅前", 35.0, 140.0),
      brbs(2, "鹿島駅前",  35.0, 140.3)  # 第 1 トークン「鹿島」 が hit
    ]
    result = StartTerminalSelector.call([ a, b, c ], line_name: "鹿島・東京線", bus_route_bus_stops: stops)
    assert_equal [ 35.0, 140.3 ], result
  end

  def test_line_name_hint_falls_back_when_match_too_far
    # 第 1 トークン「鹿島」が hit する停留所が、どの terminal からも 1km 以上離れている場合は
    # hint を採用せず multi-try に fallback。
    a = t(1, [ [ 35.0, 140.0 ], [ 35.0, 140.1 ] ])
    b = t(2, [ [ 35.0, 140.1 ], [ 35.0, 140.2 ] ])
    stops = [ brbs(1, "鹿島駅前", 36.0, 141.0) ]  # 100km 級に離れた hit
    # multi-try で同点 → westmost tiebreak。
    result = StartTerminalSelector.call([ a, b ], line_name: "鹿島線", bus_route_bus_stops: stops)
    assert_equal [ 35.0, 140.0 ], result
  end

  def test_station_hint_picks_terminal_near_station_stop
    # line_name が単一トークン「温根別」だが、bus_stop 名と部分一致がない (line_name_hint nil)。
    # 東端 terminal (35.0, 140.3) の 200m 以内に「○○駅前」があるので、station_hint が
    # 東端を採用する (westmost fallback だと西端 35.0, 140.0 が選ばれる構造)。
    a = t(1, [ [ 35.0, 140.0 ], [ 35.0, 140.1 ] ])
    b = t(2, [ [ 35.0, 140.1 ], [ 35.0, 140.2 ] ])
    c = t(3, [ [ 35.0, 140.2 ], [ 35.0, 140.3 ] ])
    stops = [
      brbs(1, "西の停留所", 35.0, 140.0),
      brbs(2, "中央駅前",   35.0, 140.30002)  # 東端から経度 ≈18m
    ]
    result = StartTerminalSelector.call([ a, b, c ], line_name: "温根別線", bus_route_bus_stops: stops)
    assert_equal [ 35.0, 140.3 ], result
  end

  def test_station_hint_returns_nil_when_no_station_within_radius
    # 「駅」を含む停留所はあるが、どの terminal からも 200m を超えて離れているため station_hint
    # は nil を返す。multi-try で同点 → westmost。
    a = t(1, [ [ 35.0, 140.0 ], [ 35.0, 140.1 ] ])
    b = t(2, [ [ 35.0, 140.1 ], [ 35.0, 140.2 ] ])
    stops = [ brbs(1, "中間駅前", 35.0, 140.1) ]  # 両端から ≈9km
    result = StartTerminalSelector.call([ a, b ], line_name: "温根別線", bus_route_bus_stops: stops)
    assert_equal [ 35.0, 140.0 ], result
  end

  def test_station_hint_picks_closest_terminal_when_both_have_station
    # 両端 terminal がともに駅近 (200m 以内) の場合、駅停留所との距離がより小さい terminal を
    # 採用する (大都市圏を想定: より「駅前らしい」方を選ぶ)。STATION_DISTANCE_BUCKET_M=50m で
    # 18m と 91m はバケットが分かれるので「東駅 (より近い)」が勝つ。
    a = t(1, [ [ 35.0, 140.0 ], [ 35.0, 140.1 ] ])
    b = t(2, [ [ 35.0, 140.1 ], [ 35.0, 140.2 ] ])
    c = t(3, [ [ 35.0, 140.2 ], [ 35.0, 140.3 ] ])
    stops = [
      brbs(1, "西駅前", 35.0, 140.001),    # 西端から ≈91m
      brbs(2, "東駅前", 35.0, 140.30002)  # 東端から ≈18m (こちらが近い)
    ]
    result = StartTerminalSelector.call([ a, b, c ], line_name: "温根別線", bus_route_bus_stops: stops)
    assert_equal [ 35.0, 140.3 ], result
  end

  def test_station_hint_picks_edge_most_terminal_when_distances_tied
    # 中間にも端にも駅 terminal があって、両者とも station 距離 0m (= 同 50m バケット) の場合、
    # 全 terminal の重心から最も遠い terminal (= 路線の geographic 端) を採用する。
    # 都01 (新橋↔渋谷) のような「中間駅 (六本木) と終端駅 (新橋) が両方 0m 一致」する case で、
    # 中間駅起点を選ぶ旧挙動 (iteration 順 tie-break) を避けて edge 起点に倒す目的。
    #
    # 構造: J を junction とし、3 本の track が J から W / S1 / S2 に伸びる。
    # 端の駅 (S2) は重心から離れているので edge と判断され、中間駅 (S1) より優先される。
    j  = [ 35.0, 140.4 ]
    w  = [ 35.0, 140.0 ]
    s1 = [ 35.0, 140.5 ]  # 中間の駅 (重心 [35.0, 140.5] に一致)
    s2 = [ 35.0, 141.0 ]  # 端の駅 (重心から 0.5 度 ≒ 50km 離れている)
    a = t(1, [ j, w  ])
    b = t(2, [ j, s1 ])
    c = t(3, [ j, s2 ])
    stops = [
      brbs(1, "中間駅", s1[0], s1[1]),
      brbs(2, "端の駅", s2[0], s2[1])
    ]
    result = StartTerminalSelector.call([ a, b, c ], line_name: "温根別線", bus_route_bus_stops: stops)
    assert_equal s2, result
  end

  def test_line_name_hint_takes_priority_over_station_hint
    # line_name 第 1 トークン「鹿島」が西端近くの停留所に hit (駅名ではない)。東端には駅近
    # 停留所がある。line_name_hint が station_hint より先に評価されるので、西端が選ばれる。
    a = t(1, [ [ 35.0, 140.0 ], [ 35.0, 140.1 ] ])
    b = t(2, [ [ 35.0, 140.1 ], [ 35.0, 140.2 ] ])
    c = t(3, [ [ 35.0, 140.2 ], [ 35.0, 140.3 ] ])
    stops = [
      brbs(1, "鹿島停留所", 35.0, 140.001),  # 西端 ≈91m、line_name token「鹿島」hit、駅なし
      brbs(2, "東駅前",     35.0, 140.30002)  # 東端 ≈18m、駅あり (station_hint だと東端)
    ]
    result = StartTerminalSelector.call([ a, b, c ], line_name: "鹿島線", bus_route_bus_stops: stops)
    assert_equal [ 35.0, 140.0 ], result
  end
end
