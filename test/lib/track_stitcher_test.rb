require "test_helper"

# DB を一切使わない PORO の単体テストなので、Minitest::Test を直接継承して
# ActiveSupport::TestCase の `fixtures :all` を回避する。
class TrackStitcherTest < Minitest::Test
  # BusRouteTrack の最小モック。`id` と `coordinates` だけを参照する PORO 前提。
  TrackDouble = Struct.new(:id, :coordinates, keyword_init: true)

  def t(id, coords)
    TrackDouble.new(id: id, coordinates: coords)
  end

  def test_empty_input_returns_empty_array
    assert_equal [], TrackStitcher.call([])
  end

  def test_single_track_returns_coords_as_is
    coords = [ [ 35.0, 140.0 ], [ 35.1, 140.1 ] ]
    assert_equal coords, TrackStitcher.call([ t(1, coords) ])
  end

  def test_tail_to_head_concatenation_dedupes_join_point
    a = t(1, [ [ 35.0, 140.0 ], [ 35.1, 140.1 ] ])
    b = t(2, [ [ 35.1, 140.1 ], [ 35.2, 140.2 ] ])
    assert_equal [ [ 35.0, 140.0 ], [ 35.1, 140.1 ], [ 35.2, 140.2 ] ], TrackStitcher.call([ a, b ])
  end

  def test_tail_to_tail_track_is_reversed
    a = t(1, [ [ 35.0, 140.0 ], [ 35.1, 140.1 ] ])
    b = t(2, [ [ 35.2, 140.2 ], [ 35.1, 140.1 ] ])
    assert_equal [ [ 35.0, 140.0 ], [ 35.1, 140.1 ], [ 35.2, 140.2 ] ], TrackStitcher.call([ a, b ])
  end

  def test_parallel_tracks_keep_longer_one
    short  = t(1, [ [ 35.0, 140.0 ], [ 35.1, 140.1 ] ])
    longer = t(2, [ [ 35.0, 140.0 ], [ 35.05, 140.05 ], [ 35.1, 140.1 ] ])
    assert_equal longer.coordinates, TrackStitcher.call([ short, longer ])
  end

  def test_parallel_tracks_with_same_size_keep_smaller_id
    a = t(1, [ [ 35.0, 140.0 ], [ 35.1, 140.1 ] ])
    b = t(2, [ [ 35.0, 140.0 ], [ 35.1, 140.1 ] ])
    # max_by { [size, -id] } なので size 同点なら -id が大きい (= id が小さい) 方が選ばれる。
    assert_equal a.coordinates, TrackStitcher.call([ a, b ])
  end

  def test_far_apart_tracks_are_still_concatenated_greedily
    # 既存ロジックは距離上限を持たないため、地理的に遠い track も常に連結される。
    # 「孤立 track の末尾追加」コードパスは現状デッドコードに近いが、挙動を固定しておく。
    a = t(1, [ [ 35.0, 140.0 ], [ 35.1, 140.1 ] ])
    far = t(2, [ [ 40.0, 145.0 ], [ 40.1, 145.1 ] ])
    assert_equal a.coordinates + far.coordinates, TrackStitcher.call([ a, far ])
  end

  def test_starting_track_is_minimum_head_longitude
    east = t(1, [ [ 35.0, 141.0 ], [ 35.1, 141.1 ] ])
    west = t(2, [ [ 35.0, 140.0 ], [ 35.1, 140.1 ] ])
    result = TrackStitcher.call([ east, west ])
    assert_equal [ 35.0, 140.0 ], result.first
  end

  def test_result_is_deterministic_regardless_of_input_order
    a = t(1, [ [ 35.0, 140.0 ], [ 35.1, 140.1 ] ])
    b = t(2, [ [ 35.1, 140.1 ], [ 35.2, 140.2 ] ])
    c = t(3, [ [ 35.2, 140.2 ], [ 35.3, 140.3 ] ])
    expected = TrackStitcher.call([ a, b, c ])
    assert_equal expected, TrackStitcher.call([ c, a, b ])
    assert_equal expected, TrackStitcher.call([ b, c, a ])
  end
end
