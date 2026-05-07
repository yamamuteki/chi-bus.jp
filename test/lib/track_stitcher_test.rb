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

  def test_starts_from_terminal_even_when_terminal_is_east_end_of_piece
    # PR #50 は piece の westmost 端点のみを終端候補としていたため、終端が piece の
    # east 側にある場合を見逃していた。両端を独立に評価することで対応する。
    # 設計: a は head=東、tail=西、tail は junction (degree 3)、head は terminal (degree 1)。
    #       b, c は junction から伸びる別 piece (head が junction)。
    # 全体の westmost 端点は a の tail (junction) だが、a の head (= 東側) も terminal。
    # 旧ロジック: a の west_end=tail (junction, degree 3) → 終端優先 fail → 全 piece の最西を選ぶ。
    # 新ロジック: a の head が terminal なので、それを起点に検討する。
    a = t(1, [ [ 35.0,  140.2 ], [ 35.0, 140.0 ] ])  # head=東 terminal, tail=西 junction
    b = t(2, [ [ 35.0,  140.0 ], [ 35.0, 139.9 ] ])  # head=junction, tail=terminal
    c = t(3, [ [ 35.0,  140.0 ], [ 35.0, 139.95 ] ])  # head=junction, tail=terminal
    result = TrackStitcher.call([ a, b, c ])
    # 終端候補: a head=140.2, b tail=139.9, c tail=139.95。最西は b tail (139.9)。
    # 起点 = b tail。b reversed (tail が起点なので)。flat 第 1 coord = b の tail。
    assert_equal [ 35.0, 139.9 ], result.first
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

  def test_leaf_spur_at_junction_inserted_before_continuing_main_route
    # 本線 a → b → c (3 track 連続)、junction (35.0, 140.1) から短い leaf spur s。
    # b と c は通常の本線 (b の終端 (35.0, 140.2) は c の head と共有 = degree 2)。
    # s は junction から degree-1 終端 (35.001, 140.1) に伸びる leaf spur。
    # 旧実装では greedy で a→b→c を先に進め、s が flat 末尾に置かれて 5km+ の
    # ジャンプが発生していた。spur 挿入により、junction で s を取り込んでから b→c へ進む。
    a = t(1, [ [ 35.0,   140.0 ], [ 35.0, 140.1 ] ])
    b = t(2, [ [ 35.0,   140.1 ], [ 35.0, 140.2 ] ])
    c = t(3, [ [ 35.0,   140.2 ], [ 35.0, 140.3 ] ])
    s = t(4, [ [ 35.0,   140.1 ], [ 35.001, 140.1 ] ])
    result = TrackStitcher.call([ a, b, c, s ])
    # 期待: a → s (spur 挿入) → 戻り → b → c
    assert_equal [ 35.0, 140.0 ], result.first
    assert_equal [ 35.0, 140.3 ], result.last  # 本線終端で終わる
    spur_idx = result.index { |coord| coord == [ 35.001, 140.1 ] }
    c_end_idx = result.index { |coord| coord == [ 35.0, 140.3 ] }
    assert spur_idx, "spur coord should appear in flat"
    assert spur_idx < c_end_idx, "spur should be inserted before route end"
  end

  def test_long_spur_is_not_inserted_at_junction
    # 物理的に長い「leaf spur」は本線の一部と推定し挿入対象外。
    # SPUR_MAX_LENGTH_M = 500m を超える spur s (~1.1km) は通常 greedy で扱われる。
    # 設計: a → b → c が本線、s は junction (35.0, 140.1) から 1.1km 北の終端へ。
    # spur 挿入が効くなら結果は a → s → b → c (s が中間) だが、長すぎるので無効化されて
    # a → b → c → s (s が末尾) のほうが起こりやすい。「s が末尾に置かれること」を確認する
    # ことで「長い spur は挿入されない」挙動を検証する。
    a = t(1, [ [ 35.0,  140.0 ], [ 35.0, 140.1 ] ])
    b = t(2, [ [ 35.0,  140.1 ], [ 35.0, 140.2 ] ])
    c = t(3, [ [ 35.0,  140.2 ], [ 35.0, 140.3 ] ])
    s = t(4, [ [ 35.0,  140.1 ], [ 35.01, 140.1 ] ])  # 約 1.1km, 500m 超
    result = TrackStitcher.call([ a, b, c, s ])
    spur_idx = result.index { |coord| coord == [ 35.01, 140.1 ] }
    c_end_idx = result.index { |coord| coord == [ 35.0, 140.3 ] }
    assert spur_idx, "spur coord should still appear in flat (just not inserted at junction)"
    # 長い spur は junction で挿入されず、greedy が本線後に末尾近くで取り込む。
    # = c の終端より後ろに spur 終端が出る。
    assert spur_idx > c_end_idx, "long spur should be deferred, not inserted at junction"
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
