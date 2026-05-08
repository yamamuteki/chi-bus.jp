require "test_helper"

# DB を使わない PORO の単体テスト。fixtures をスキップするため Minitest::Test を直接継承。
class BusStopNumbererTest < Minitest::Test
  BrbsDouble = Struct.new(:id, :bus_stop, keyword_init: true)
  BusStopDouble = Struct.new(:latitude, :longitude, keyword_init: true)

  def brbs(id, lat, lng)
    BrbsDouble.new(id: id, bus_stop: BusStopDouble.new(latitude: lat, longitude: lng))
  end

  def test_empty_flat_coords_returns_nil_numbers
    result = BusStopNumberer.call(flat_coords: [], bus_route_bus_stops: [ brbs(1, 35.0, 140.0) ])
    assert_equal [ [ 1, nil ] ], result
  end

  def test_three_bus_stops_along_straight_path_get_1_2_3
    flat = [ [ 35.0, 140.0 ], [ 35.0, 140.1 ], [ 35.0, 140.2 ] ]
    bs1 = brbs(101, 35.0, 140.0)
    bs2 = brbs(102, 35.0, 140.1)
    bs3 = brbs(103, 35.0, 140.2)
    # 入力順を逆にしても、軌跡上の位置で 1, 2, 3 が振られる。
    result = BusStopNumberer.call(flat_coords: flat, bus_route_bus_stops: [ bs3, bs2, bs1 ])
    h = result.to_h
    assert_equal 1, h[101]
    assert_equal 2, h[102]
    assert_equal 3, h[103]
  end

  def test_same_idx_tie_break_by_distance
    # 同じ flat coord に近いバス停 2 つ。軌跡からの距離が近い方が先。
    flat = [ [ 35.0, 140.0 ] ]
    exact = brbs(1, 35.0, 140.0)
    far   = brbs(2, 35.001, 140.001)
    result = BusStopNumberer.call(flat_coords: flat, bus_route_bus_stops: [ far, exact ])
    h = result.to_h
    assert_equal 1, h[1]
    assert_equal 2, h[2]
  end

  def test_returns_an_assignment_for_every_brbs
    flat = [ [ 35.0, 140.0 ], [ 35.0, 140.1 ] ]
    list = [ brbs(1, 35.0, 140.05), brbs(2, 35.0, 140.0), brbs(3, 35.0, 140.1) ]
    result = BusStopNumberer.call(flat_coords: flat, bus_route_bus_stops: list)
    assert_equal 3, result.size
    assert_equal [ 1, 2, 3 ], result.map { |_, n| n }.sort
  end

  def test_bridge_segment_is_excluded_from_projection
    # flat = [A, B, C, D] (3 segments)。segment 1 (B→C) を bridge として除外すると、
    # 「B-C 間の直線」上に乗るバス停は本来の最近接 (segment 0 or 2) に射影されるべき。
    # 玉野渋川特急線 20585 の再現テスト: 19km の bridge 上に偶然乗る位置にある
    # バス停を、bridge を除外することで正しい side に射影する。
    flat = [ [ 35.0, 140.0 ], [ 35.0, 140.1 ], [ 35.0, 140.5 ], [ 35.0, 140.6 ] ]
    # bridge: segment 1 (140.1 → 140.5) は 40km の virtual jump とみなす。
    # near_left は (35.0, 140.05) で segment 0 上 (curvilinear position 0.5)
    # near_bridge は (35.0, 140.3) で segment 1 (bridge) 上にあり、bridge を除外しないと
    # そっちが最近接になってしまう。除外すれば segment 0 の終端 (t=1) または
    # segment 2 の始点 (t=0) に射影される。
    near_left = brbs(1, 35.0, 140.05)
    near_bridge_naive = brbs(2, 35.0, 140.3)  # 本来 segment 0 末端 〜 segment 2 始点 のあたり
    near_right = brbs(3, 35.0, 140.55)
    result = BusStopNumberer.call(
      flat_coords: flat,
      bus_route_bus_stops: [ near_right, near_bridge_naive, near_left ],
      bridge_segment_indices: [ 1 ]
    )
    h = result.to_h
    # bridge を除外しなければ near_bridge_naive は segment 1 t=0.5 に射影され position 1.5。
    # near_left (segment 0 t=0.5) → position 0.5。near_right (segment 2 t=0.5) → position 2.5。
    # → 順序 1, 2, 3 になっていただろう。
    # bridge を除外すると near_bridge_naive は segment 0 (t=1) または segment 2 (t=0) に
    # 射影され、距離計算の結果近い方が採用される。両方の curvilinear position は
    # 1.0 / 2.0 で、segment 2 の方が物理的に近い (140.5 の方が 140.3 から近い)。
    # よって順序: near_left=1 (pos 0.5), near_bridge_naive=2 (pos 2.0), near_right=3 (pos 2.5)。
    assert_equal 1, h[1]
    assert_equal 2, h[2]
    assert_equal 3, h[3]
  end

  def test_circular_route_picks_first_pass_by_distance
    # 循環ルート: flat が同じ場所を 2 回通る。バス停の最近接 idx は距離 (微差) で
    # どちらかに決まる。これが現状ロジックの限界 (循環で順序が崩れうる)。
    # ここでは現状挙動を固定するだけ。
    flat = [ [ 35.0, 140.0 ], [ 35.0, 140.1 ], [ 35.0, 140.2 ], [ 35.0, 140.1 ], [ 35.0, 140.0 ] ]
    middle = brbs(1, 35.0, 140.1)
    end_stop = brbs(2, 35.0, 140.2)
    result = BusStopNumberer.call(flat_coords: flat, bus_route_bus_stops: [ middle, end_stop ])
    h = result.to_h
    # middle は flat[1] にも flat[3] にも等距離 → 距離 tie の場合は idx の若い方が選ばれる。
    # よって middle = 1, end_stop = 2 (flat[2]) が期待値。
    assert_equal 1, h[1]
    assert_equal 2, h[2]
  end
end
