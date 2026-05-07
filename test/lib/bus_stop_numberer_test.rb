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
