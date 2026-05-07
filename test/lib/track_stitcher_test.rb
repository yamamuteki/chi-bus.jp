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

  def test_parallel_tracks_with_different_coords_keep_both
    # head/tail が同じでも coords が異なる場合 = 行き帰りで別経路の並行軌跡。
    # primary (coords 多い方) を outbound で利用、alternate (残り) を return phase で
    # 反転して連結。これにより往復モデルが実現し UI 描画と numbering が整合する。
    short  = t(1, [ [ 35.0, 140.0 ], [ 35.1, 140.1 ] ])  # alternate (coords 少ない)
    longer = t(2, [ [ 35.0, 140.0 ], [ 35.05, 140.05 ], [ 35.1, 140.1 ] ])  # primary
    result = TrackStitcher.call([ short, longer ])
    # 期待: longer forward (outbound) → short reversed (return phase) で dedup。
    # = [(35.0, 140.0), (35.05, 140.05), (35.1, 140.1), (35.0, 140.0)]
    assert_equal [ [ 35.0, 140.0 ], [ 35.05, 140.05 ], [ 35.1, 140.1 ], [ 35.0, 140.0 ] ], result
  end

  def test_parallel_tracks_with_identical_coords_keep_one
    # head/tail と coords が完全一致 = 真の重複。id 最小を 1 本だけ残す。
    a = t(1, [ [ 35.0, 140.0 ], [ 35.1, 140.1 ] ])
    b = t(2, [ [ 35.0, 140.0 ], [ 35.1, 140.1 ] ])
    assert_equal a.coordinates, TrackStitcher.call([ a, b ])
  end

  def test_short_span_parallel_tracks_with_different_coords_dedup_to_longest
    # head/tail が一致するが coords 数が違う + 端点間距離が短い (≤500m) 場合は、
    # 解像度違いで描かれた同一の短セグメントとみなして coords 数最大を残し、
    # 残りは捨てる (alternate にしない)。
    # 例: 玉野渋川特急線 20585 で track 63935 (3 coords) と 63945 (6 coords) が
    # head=tail=同一短セグメント (~63m) として並行軌跡判定されてしまい、return phase で
    # 19km の bridge segment が発生して 玉野営業所前 が誤って末尾に並んだバグ。
    short  = t(1, [ [ 35.0, 140.0 ], [ 35.0001, 140.0001 ] ])  # 端点間 ~14m
    longer = t(2, [ [ 35.0, 140.0 ], [ 35.00005, 140.00005 ], [ 35.0001, 140.0001 ] ])
    result = TrackStitcher.call_with_diagnostics([ short, longer ])
    # longer のみ採用、short は skipped。
    assert_equal 1, result.skipped_parallel
    assert_equal [ 2 ], result.stitch_steps.map(&:track_id)
    assert_equal longer.coordinates, result.flat_coords
  end

  def test_parallel_alternate_is_deferred_to_return_phase
    # 往復モデル: outbound phase は primary のみ使用。alternate (= 並行軌跡パートナー)
    # は outbound 完了後の return phase で利用される。
    # 構造: north terminal a → 並行軌跡 (b primary, c alternate) → south terminal d
    # outbound: a → b → d (terminal 到達) → e_spur 経由
    # return: alternate c で逆向きに戻る
    a = t(1, [ [ 35.2, 140.0 ], [ 35.1, 140.0 ] ])  # north 端 (terminal)
    b = t(2, [ [ 35.1, 140.0 ], [ 35.05, 140.05 ], [ 35.0, 140.0 ] ])  # 西経路 (primary, 3 coords)
    c = t(3, [ [ 35.1, 140.0 ], [ 35.0, 140.0 ] ])  # 東経路 (alternate, 2 coords)
    d = t(4, [ [ 35.0, 140.0 ], [ 34.9, 140.0 ] ])  # south 端 (terminal)
    result = TrackStitcher.call_with_diagnostics([ a, b, c, d ])
    # 期待 stitch_steps:
    #   1. a (北端 terminal 起点)
    #   2. b primary (outbound 西経路)
    #   3. d (continue south)
    #   4. c alternate (return phase で 反転利用)
    track_ids = result.stitch_steps.map(&:track_id)
    # a, b, d が outbound で先に並ぶ。c は最後 (return phase)。
    assert_equal [ 1, 2, 4, 3 ], track_ids
  end

  def test_parallel_outbound_and_return_paths_concatenate_via_shared_endpoint
    # 行き帰りで別経路の並行軌跡 (head/tail 共有、coords 異なる) を両方保持。
    # 一方を forward、もう一方を共通 endpoint で連続して reversed として連結する。
    # 例: 坂東市 5985 では 21646 (西経路) と 21647 (東経路) が同じ南北端点を共有。
    a = t(1, [ [ 35.0, 140.0 ], [ 35.05, 140.0 ], [ 35.1, 140.0 ] ])  # 西経路
    b = t(2, [ [ 35.0, 140.0 ], [ 35.05, 140.05 ], [ 35.1, 140.0 ] ])  # 東経路 (中央が東寄り)
    result = TrackStitcher.call([ a, b ])
    # a forward → b reversed の連結を期待。
    # flat: a coords + b coords reversed (共通 endpoint で dedup)
    # = [(35.0, 140.0), (35.05, 140.0), (35.1, 140.0), (35.05, 140.05), (35.0, 140.0)]
    assert_equal [ [ 35.0, 140.0 ], [ 35.05, 140.0 ], [ 35.1, 140.0 ], [ 35.05, 140.05 ], [ 35.0, 140.0 ] ], result
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

  def test_bridge_segment_indices_record_virtual_joins
    # track 間が「coord 完全一致せず」連結されたとき、その境界の segment は実体のない
    # virtual bridge。flat_coords[i] -> flat_coords[i+1] の i を記録する。
    a = t(1, [ [ 35.0, 140.0 ], [ 35.1, 140.0 ] ])  # 2 coords (segment index 0)
    b = t(2, [ [ 35.2, 140.0 ], [ 35.3, 140.0 ] ])  # not connected to a
    result = TrackStitcher.call_with_diagnostics([ a, b ])
    # flat = [(35.0,140.0), (35.1,140.0), (35.2,140.0), (35.3,140.0)] (4 coords, 3 segments)
    # segment 0: 真 (a 内)、segment 1: bridge (a 終端 → b 始点)、segment 2: 真 (b 内)
    assert_equal 4, result.flat_coords.size
    assert_equal [ 1 ], result.bridge_segment_indices
  end

  def test_bridge_segment_indices_empty_when_perfectly_joined
    a = t(1, [ [ 35.0, 140.0 ], [ 35.1, 140.0 ] ])
    b = t(2, [ [ 35.1, 140.0 ], [ 35.2, 140.0 ] ])  # a の tail と b の head が完全一致
    result = TrackStitcher.call_with_diagnostics([ a, b ])
    # 連結時に重複点を dedup するので bridge segment は発生しない。
    assert_equal [], result.bridge_segment_indices
  end

  def test_explicit_start_overrides_westmost_default
    # start: で明示した coord が degree-1 terminal なら、最西端ヒューリスティックを上書きして
    # その coord から開始する。
    a = t(1, [ [ 35.0, 140.0 ], [ 35.0, 140.1 ] ])
    b = t(2, [ [ 35.0, 140.1 ], [ 35.0, 140.2 ] ])
    # 通常 (start 未指定) は westmost = (35.0, 140.0)
    assert_equal [ 35.0, 140.0 ], TrackStitcher.call([ a, b ]).first
    # start = east end → そこから始まる (反転)
    assert_equal [ 35.0, 140.2 ], TrackStitcher.call([ a, b ], start: [ 35.0, 140.2 ]).first
  end

  def test_explicit_start_falls_back_when_coord_not_terminal
    # start で渡した coord が terminal でない (= 存在しない or junction) 場合は
    # 既定の最西端 fallback に戻る。
    a = t(1, [ [ 35.0, 140.0 ], [ 35.0, 140.1 ] ])
    b = t(2, [ [ 35.0, 140.1 ], [ 35.0, 140.2 ] ])
    # ありえない coord
    assert_equal [ 35.0, 140.0 ], TrackStitcher.call([ a, b ], start: [ 99.0, 99.0 ]).first
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
