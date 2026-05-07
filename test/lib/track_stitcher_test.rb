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

  def test_starts_from_degree_one_endpoint_when_available
    # 端点重複度 1 = 路線の物理的終端と推定。terminal がある場合は最西端 terminal を優先する。
    # 中央 (35.05, 140.05) を 3 track が共有 = degree 3 (重複)。terminal 候補は a の 140.0、
    # b の 140.1、c の 140.05 のうち、a の 140.0 が最西。
    a = t(1, [ [ 35.0, 140.0 ], [ 35.05, 140.05 ] ])
    b = t(2, [ [ 35.05, 140.05 ], [ 35.0, 140.1 ] ])
    c = t(3, [ [ 35.05, 140.05 ], [ 35.1, 140.05 ] ])
    result = TrackStitcher.call([ a, b, c ])
    # a の terminal (140.0) から開始するため、最初の coord は (35.0, 140.0)
    assert_equal [ 35.0, 140.0 ], result.first
  end

  def test_falls_back_to_westmost_when_no_degree_one_endpoint
    # 純粋な循環ルート (全 endpoint が degree 2): terminal がないため最西端起点に fallback。
    # head/tail がリングを構成: a→b→c→a。
    a = t(1, [ [ 35.0, 140.0 ], [ 35.1, 140.0 ] ])
    b = t(2, [ [ 35.1, 140.0 ], [ 35.05, 140.05 ] ])
    c = t(3, [ [ 35.05, 140.05 ], [ 35.0, 140.0 ] ])
    result = TrackStitcher.call([ a, b, c ])
    # 最西端 = (35.0, 140.0) または (35.1, 140.0)。両者 lng=140.0 で id tie-break で a の head (35.0, 140.0)。
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
