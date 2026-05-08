# bus_stop_number の向きを `bus_route.line_name` の地名ヒントで補正する。
#
# line_name には「○○～△△」「○○・◇◇～△△」のような区切り付きの地名列が含まれる
# ことが多い (chi-bus.jp 内で約 17%)。stitcher は最西端起点という地理的ヒューリスティック
# だけで起点を決めているため、line_name の意図 (○○発、△△着) と逆向きに採番される
# ケースが survey 上 322 路線中 149 (46%) もあった。
#
# 実装: line_name を区切りで split → 各 token を bus_stop 名に部分一致照合 →
# 2 つ以上 match した bus_stop の bus_stop_number を取り、降順なら全反転 (= max+1 - num)。
# 順不同 (部分的にズレ) は判断保留 (= 反転しない)。
class LineNameOrienter
  # 地名以外と思われる token を弾くパターン。
  # 「前橋」「鹿島」のような 2 文字地名は弾かないよう、長さ判定は別途 length < 2 で行う。
  NON_PLACE_RE = /\A(?:線|ルート|号|急行|方面|経由|系統|コース|本線|支線|間|発|行き?|便|号線)\z/

  # 区切り (読点・中黒・矢印・波ダッシュ・⇔・全角/半角空白・ハイフン・全角/半角括弧)。
  # 括弧は「○○線（○○経由）」のように補足区分として使われるので、内部を独立 token として
  # 取り出すために区切り扱いする。「東経由」「市役所」のような汎用 token は後段の
  # NON_PLACE_RE / 部分一致で結局 hit しないか、unique terminal に対応しないので無害。
  SEPARATOR_RE = /[、・→〜～⇔　\s\-（）()]+/

  # 末尾の不要 suffix を剥がすパターン。「○○駅線」「○○ルート」のような token から
  # 末尾の修飾語を除去すると、bus_stop 名 (「○○駅」など) との部分一致率が上がる。
  TRAILING_SUFFIX_RE = /(?:線|ルート|コース|便|号|系統|系|急行|特急|発|行き?)\z/

  # 先頭の不要 prefix を剥がすパターン。「1-7鴨川」のような行先番号付き token を清める。
  LEADING_PREFIX_RE = /\A[\d\-]+/

  # bus_stop_number の向きを補正した assignments を返す。
  # 反転判定に該当しない場合は引数をそのまま返す。
  #
  # @param bus_route [BusRoute]
  # @param brbs_list [Array<BusRouteBusStop>] (bus_stop association を eager load しておくこと)
  # @param assignments [Array<[id, bus_stop_number]>]
  # @return [Array<[id, bus_stop_number]>]
  def self.call(bus_route, brbs_list, assignments)
    new(bus_route, brbs_list, assignments).call
  end

  # line_name から地名 token を抽出する。stitch 起点選択 (StartTerminalSelector) でも
  # 同じ token を使うため class method で公開している。
  # 括弧は SEPARATOR_RE で区切るため、内部 token は別途取り出される (例: 「○○線（東口）」 →
  # ["○○", "東口"])。汎用語は NON_PLACE_RE / bus_stop 部分一致で自然に絞られる。
  def self.parse_tokens(line_name)
    return [] if line_name.nil? || line_name.empty?
    normalized = line_name.gsub(/(?<!\p{Katakana})ー/, "-")
    normalized.split(SEPARATOR_RE).map { |t|
      cleaned = t.gsub(LEADING_PREFIX_RE, "")
      cleaned = cleaned.sub(TRAILING_SUFFIX_RE, "") while cleaned.match?(TRAILING_SUFFIX_RE)
      cleaned
    }.reject { |t| t.empty? || t.length < 2 || NON_PLACE_RE === t }
  end

  def initialize(bus_route, brbs_list, assignments)
    @bus_route = bus_route
    @brbs_list = brbs_list
    @assignments = assignments
  end

  def call
    tokens = parse_tokens(@bus_route.line_name)
    return @assignments if tokens.size < 2

    # token → 該当 bus_stop_number に変換。同じ bus_stop_number は重複させない
    # (= 同じ bus_stop が複数 token に hit するケースをスキップ)。
    num_by_brbs_id = @assignments.to_h
    matched_numbers = []
    seen_ids = {}
    tokens.each do |tok|
      brbs = @brbs_list.find { |b| b.bus_stop.name.include?(tok) }
      next unless brbs
      next if seen_ids[brbs.id]
      seen_ids[brbs.id] = true
      num = num_by_brbs_id[brbs.id]
      matched_numbers << num if num
    end

    return @assignments if matched_numbers.size < 2
    return @assignments unless matched_numbers == matched_numbers.sort.reverse

    # 全反転: new_num = total + 1 - old_num
    total = @assignments.count { |_, n| !n.nil? }
    @assignments.map { |id, num| [ id, num.nil? ? nil : total + 1 - num ] }
  end

  private

  def parse_tokens(line_name)
    self.class.parse_tokens(line_name)
  end
end
