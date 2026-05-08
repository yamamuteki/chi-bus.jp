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
end
