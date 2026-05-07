require "test_helper"

# DB を使わない PORO の単体テスト。fixtures をスキップするため Minitest::Test を直接継承。
class LineNameOrienterTest < Minitest::Test
  RouteDouble = Struct.new(:line_name, keyword_init: true)
  BrbsDouble = Struct.new(:id, :bus_stop, keyword_init: true)
  StopDouble = Struct.new(:name, keyword_init: true)

  def brbs(id, name)
    BrbsDouble.new(id: id, bus_stop: StopDouble.new(name: name))
  end

  def test_returns_input_when_line_name_is_blank
    route = RouteDouble.new(line_name: "")
    list = [ brbs(1, "東京駅"), brbs(2, "渋谷駅") ]
    assignments = [ [ 1, 1 ], [ 2, 2 ] ]
    assert_equal assignments, LineNameOrienter.call(route, list, assignments)
  end

  def test_returns_input_when_no_separator_found
    route = RouteDouble.new(line_name: "シリウス号")
    list = [ brbs(1, "シリウス"), brbs(2, "東京駅") ]
    assignments = [ [ 1, 1 ], [ 2, 2 ] ]
    assert_equal assignments, LineNameOrienter.call(route, list, assignments)
  end

  def test_returns_input_when_only_one_token_matches
    # token=東京 だけ match (鹿島は match しない) → 反転判定不能でそのまま返す。
    route = RouteDouble.new(line_name: "鹿島～東京")
    list = [ brbs(1, "東京駅前"), brbs(2, "別の場所") ]
    assignments = [ [ 1, 1 ], [ 2, 2 ] ]
    assert_equal assignments, LineNameOrienter.call(route, list, assignments)
  end

  def test_reverses_when_matched_numbers_are_strictly_decreasing
    # line_name は "東京駅～鹿島神宮" → token 順 [東京駅, 鹿島神宮]
    # 現状 num: 東京駅=3, 鹿島神宮=1 → [3, 1] = 降順 → 反転
    route = RouteDouble.new(line_name: "東京駅～鹿島神宮")
    list = [
      brbs(10, "鹿島神宮駅"),
      brbs(20, "中間"),
      brbs(30, "東京駅前")
    ]
    assignments = [ [ 30, 3 ], [ 20, 2 ], [ 10, 1 ] ]
    result = LineNameOrienter.call(route, list, assignments).to_h
    # total=3 → 反転後: 旧 1 → 新 3, 旧 2 → 新 2, 旧 3 → 新 1
    assert_equal 1, result[30]   # 東京駅前 が #1 に
    assert_equal 2, result[20]
    assert_equal 3, result[10]   # 鹿島神宮駅 が #3 に
  end

  def test_does_not_reverse_when_matched_numbers_are_increasing
    # line_name は "東京駅～鹿島神宮" → token 順 [東京駅, 鹿島神宮]
    # 現状 num: 東京駅=1, 鹿島神宮=3 → [1, 3] = 増加順 → 既に正
    route = RouteDouble.new(line_name: "東京駅～鹿島神宮")
    list = [
      brbs(10, "東京駅前"),
      brbs(20, "中間"),
      brbs(30, "鹿島神宮駅")
    ]
    assignments = [ [ 10, 1 ], [ 20, 2 ], [ 30, 3 ] ]
    assert_equal assignments, LineNameOrienter.call(route, list, assignments)
  end

  def test_does_not_reverse_when_partially_disordered
    # 3 token match で 部分的にズレている → 単純反転では直らないので何もしない。
    route = RouteDouble.new(line_name: "A～B～C")
    list = [
      brbs(10, "A駅前"),
      brbs(20, "B駅前"),
      brbs(30, "C駅前")
    ]
    # A=2, B=1, C=3 → [2, 1, 3] = 増加でも降順でもない
    assignments = [ [ 10, 2 ], [ 20, 1 ], [ 30, 3 ] ]
    assert_equal assignments, LineNameOrienter.call(route, list, assignments)
  end

  def test_filters_out_non_place_tokens
    # 「線」「ルート」「号」等のノイズ token を弾く。
    route = RouteDouble.new(line_name: "東京駅～千葉駅線")
    list = [ brbs(1, "東京駅前"), brbs(2, "千葉駅西口") ]
    # 「線」が token 化されても hit しないので問題ないが、念のため弾けることを確認。
    # ここでは parse_tokens の挙動だけ確認したいので、増加順の状況にしておく。
    assignments = [ [ 1, 1 ], [ 2, 2 ] ]
    assert_equal assignments, LineNameOrienter.call(route, list, assignments)
  end

  def test_handles_middle_dot_separator_with_three_tokens
    # 「○○・△△～□□」のような中継地点付きパターン。
    # token 順: [前橋, 高崎, 新潟] が降順なら反転。
    route = RouteDouble.new(line_name: "前橋・高崎～新潟")
    list = [
      brbs(1, "新潟駅前"),
      brbs(2, "高崎駅前"),
      brbs(3, "前橋駅前")
    ]
    # 現状: 新潟=1, 高崎=2, 前橋=3 → token 順での num [3, 2, 1] = 降順 → 反転
    assignments = [ [ 1, 1 ], [ 2, 2 ], [ 3, 3 ] ]
    result = LineNameOrienter.call(route, list, assignments).to_h
    assert_equal 3, result[1]   # 新潟が #3 に
    assert_equal 2, result[2]
    assert_equal 1, result[3]   # 前橋が #1 に
  end

  def test_strips_trailing_line_suffix_from_tokens
    # token "横浜駅線" は末尾の「線」を剥がして "横浜駅" として扱い、bus_stop に部分一致させる。
    route = RouteDouble.new(line_name: "五井駅～横浜駅線")
    list = [
      brbs(1, "横浜駅東口"),
      brbs(2, "中間"),
      brbs(3, "五井駅前")
    ]
    # 五井駅 → 五井駅前 (#3)、横浜駅 → 横浜駅東口 (#1)。matched=[3, 1] = 降順 → 反転。
    assignments = [ [ 1, 1 ], [ 2, 2 ], [ 3, 3 ] ]
    result = LineNameOrienter.call(route, list, assignments).to_h
    assert_equal 3, result[1]   # 横浜駅東口 が #3 に
    assert_equal 1, result[3]   # 五井駅前 が #1 に
  end

  def test_strips_leading_number_prefix_from_tokens
    # token "1-7鴨川" は先頭の "1-7" を剥がして "鴨川" として扱う。
    route = RouteDouble.new(line_name: "1-7鴨川・木更津線")
    list = [ brbs(1, "木更津駅東口"), brbs(2, "鴨川駅前") ]
    # 鴨川 → 鴨川駅前 (#2)、木更津 → 木更津駅東口 (#1)。降順 → 反転。
    assignments = [ [ 1, 1 ], [ 2, 2 ] ]
    result = LineNameOrienter.call(route, list, assignments).to_h
    assert_equal 2, result[1]   # 木更津駅東口 が #2 に
    assert_equal 1, result[2]   # 鴨川駅前 が #1 に
  end

  def test_treats_long_sound_mark_between_kanji_as_separator
    # 「ー」(U+30FC) は katakana 音引きが通常用途だが、漢字に挟まれた場合は
    # 区切りとして使われる (例: 「高崎駅ー南陽台線」)。
    route = RouteDouble.new(line_name: "高崎駅ー南陽台線")
    list = [ brbs(1, "南陽台入口"), brbs(2, "高崎駅東口") ]
    # 高崎駅 → 高崎駅東口 (#2)、南陽台 → 南陽台入口 (#1)。降順 → 反転。
    assignments = [ [ 1, 1 ], [ 2, 2 ] ]
    result = LineNameOrienter.call(route, list, assignments).to_h
    assert_equal 2, result[1]   # 南陽台入口 が #2 に
    assert_equal 1, result[2]   # 高崎駅東口 が #1 に
  end

  def test_does_not_treat_long_sound_mark_in_katakana_word_as_separator
    # 「ポーラスター」のような katakana 語では ー は音引き。区切り扱いせず token を保持。
    route = RouteDouble.new(line_name: "ポーラスター")
    list = [ brbs(1, "ポーラスター本社"), brbs(2, "他") ]
    # 区切りは無く tokens は ["ポーラスター"] のはず。1 token のみで反転判定不能でそのまま返す。
    assignments = [ [ 1, 1 ], [ 2, 2 ] ]
    assert_equal assignments, LineNameOrienter.call(route, list, assignments)
  end

  def test_handles_nil_bus_stop_number_in_assignments
    # 一部 brbs に bus_stop_number が nil の場合、nil は反転対象外で nil のまま。
    route = RouteDouble.new(line_name: "東京駅～鹿島")
    list = [ brbs(1, "東京駅前"), brbs(2, "鹿島駅前"), brbs(3, "他") ]
    assignments = [ [ 1, 2 ], [ 2, 1 ], [ 3, nil ] ]
    result = LineNameOrienter.call(route, list, assignments).to_h
    # total=2 → 反転後: 1→2, 2→1, nil → nil
    assert_equal 1, result[1]
    assert_equal 2, result[2]
    assert_nil result[3]
  end
end
