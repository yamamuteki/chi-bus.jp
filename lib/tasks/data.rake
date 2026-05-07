# db/ksj/n07/N07-11_*.xml.gz（路線）と db/ksj/p11/P11-10_*-jgd-g.xml.gz（バス停）を解析して
# db/data/*.csv を生成・DB に投入する rake タスク。
#
# データソースは「国土数値情報」（国土交通省）。XML は重く、`generate` は
# ローカルで実行して結果（CSV）を git にコミットする運用。`load` は CSV を
# PostgreSQL の COPY FROM STDIN で流し込む高速ロードで、Heroku 上でも数十秒で完了する。
#
# 派生データ（bus_stop_number / 住所情報 / keyword）は別タスク群が独立した CSV を持って
# bulk UPDATE で投入する。data:load の後に bus_stop_number:load / geocode:load /
# keyword:load を順次呼ぶと完成形の DB になる（db/seeds.rb 参照）。
#
# クラスをファイル先頭に置いているのは、rake namespace 内に書くと定数解決が
# やや煩雑になるため。lib/tasks/ は Rails の autoload 対象外なので、トップレベルに
# クラスを置いても eager_load 衝突は起きない。
class DataGenerator
  # 国土数値情報の都道府県コード（08〜14 = 茨城〜神奈川）と表示用の県名。
  # 北関東 3 県を含むのは、隣県をまたぐ路線・バス停を漏らさず取り込むため。
  PREFECTURES = {
    "12" => "千葉県",
    "13" => "東京都",
    "14" => "神奈川県",
    "11" => "埼玉県",
    "08" => "茨城県",
    "09" => "栃木県",
    "10" => "群馬県"
  }.freeze

  # XML のファイル命名規則。`%s` に都道府県コードを差し込んで使う。
  # データソースを差し替える際はここ 1 箇所を直せば済む。
  # 国土数値情報の XML は容量が大きいため gzip 圧縮して .xml.gz として
  # 保存・読み込みする (open_xml で透過解凍)。
  ROUTE_XML_FORMAT = "db/ksj/n07/N07-11_%s.xml.gz".freeze
  STOP_XML_FORMAT  = "db/ksj/p11/P11-10_%s-jgd-g.xml.gz".freeze

  def initialize
    @now = Time.zone.now

    # 各テーブルに投入する行データ（Hash の配列）。最後にまとめて CSV に書き出す。
    @bus_route_tracks    = []
    @bus_routes          = []
    @bus_stops           = []
    @bus_route_bus_stops = []

    # XML パース中の参照解決用インデックス。
    # @track_id_by_gml: Curve 要素の GML id → bus_route_tracks の連番 id。
    #   後段の BusRoute から `brt[href]` で track を引くために使う。
    # @route_id_by_key: 路線の属性タプル → bus_routes の連番 id。
    #   同一属性の路線が県境で重複定義されているのを 1 行に集約する。
    # @track_coords_by_id: track_id → 簡略化済み coords 配列。CSV 用の JSON 文字列とは別に
    #   配列を保持しておき、link_stop_to_routes の最近接判定で使う。
    @track_id_by_gml = {}
    @route_id_by_key = {}
    @track_coords_by_id = {}
    # 座標ハッシュ → track_id。県境を跨ぐ Curve は両県の N07 ファイルに
    # 同一座標で重複登録されているため、ここで dedup する。
    @track_id_by_coord_hash = {}
  end

  # エントリポイント。XML パース → CSV 書き出しの順に実行。
  # bus_stop_number / 住所情報 / keyword などの派生データは別タスク (bus_stop_number:generate /
  # geocode:generate / keyword:generate) が独立して CSV を生成・load する責務。
  def run
    PREFECTURES.each_key { |code| parse_route_xml(code) }
    build_route_lookup
    PREFECTURES.each { |code, prefecture| parse_stop_xml(code, prefecture) }
    write_all_csv
  end

  private

  # ---------------------------------------------------------------------------
  # 1. 路線 XML のパース（Curve = 軌跡 / BusRoute = 路線情報）
  # ---------------------------------------------------------------------------

  def parse_route_xml(code)
    xml_path = ROUTE_XML_FORMAT % code
    doc = open_xml(xml_path)
    extract_tracks(doc, xml_path, code)
    extract_routes(doc, xml_path, code)
  end

  # Curve 要素 = 路線の軌跡（座標列）。
  # ・座標列は SimplifyRb で間引いて軽量化（許容誤差 0.0001 度 ≒ 約 11m）
  # ・JSON は手書きで生成。json gem の Float#to_json は 17 桁出してしまうため、
  #   Float#to_s（最短ラウンドトリップ表現）を使ってサイズを抑える。
  def extract_tracks(doc, xml_path, code)
    nodes = doc.css("Curve")
    added = 0
    deduped = 0
    nodes.each do |node|
      gml_id = "#{xml_path}/#{node['id']}"
      coordinates = parse_coordinates(node.at("posList").text)

      # 県境を跨ぐ Curve は隣県の N07 ファイルに同一座標で重複登録されている
      # (実測 7 県分 26,862 curves 中 6,504 件 ≒ 24% が重複)。ここで座標 hash で dedup
      # して bus_route_tracks の行数を減らす。後段の extract_routes が brt[href] で
      # gml_id 経由で track を引くため、@track_id_by_gml は dedup 後の track_id を指す。
      coord_hash = coordinates.hash
      if (existing_track_id = @track_id_by_coord_hash[coord_hash])
        @track_id_by_gml[gml_id] = existing_track_id
        deduped += 1
        next
      end

      simplified = simplify_coordinates(coordinates)
      track_id = @bus_route_tracks.size + 1
      @bus_route_tracks << {
        id: track_id,
        gml_id: gml_id,
        coordinates: coordinates_to_compact_json(simplified),
        bus_route_id: nil, # extract_routes で後付けする
        created_at: @now,
        updated_at: @now
      }
      @track_id_by_gml[gml_id] = track_id
      @track_id_by_coord_hash[coord_hash] = track_id
      @track_coords_by_id[track_id] = simplified
      added += 1
    end
    puts "  Tracks #{code}: #{nodes.size} curves (#{added} added, #{deduped} dedup)"
  end

  # BusRoute 要素 = 路線属性。
  # ・同一属性（種別/会社/路線名/運賃...）の路線は 1 行に集約
  # ・brt[href] が指す Curve（= bus_route_tracks の行）の bus_route_id を逆向きに埋める
  def extract_routes(doc, xml_path, code)
    nodes = doc.css("BusRoute")
    nodes.each do |node|
      attrs = {
        bus_type:          node.at("bsc").text.to_i,
        operation_company: node.at("boc").text,
        line_name:         node.at("bln").text,
        weekday_rate:      node.at("rpd").text.to_f,
        saturday_rate:     node.at("rps").text.to_f,
        holiday_rate:      node.at("rph").text.to_f,
        note:              node.at("rmk").text
      }
      route_id = find_or_create_route(attrs)

      # この BusRoute に紐づく Curve の bus_route_id を埋める
      track_gml = "#{xml_path}/#{node.at('brt')['href'].remove('#')}"
      if (track_id = @track_id_by_gml[track_gml])
        @bus_route_tracks[track_id - 1][:bus_route_id] = route_id
      end
    end
    puts "  Routes #{code}: #{nodes.size} routes"
  end

  # 既存の同一属性 route があればその id を返し、無ければ新規作成して id を返す。
  def find_or_create_route(attrs)
    key = attrs.values_at(:bus_type, :operation_company, :line_name, :weekday_rate, :saturday_rate, :holiday_rate, :note)
    @route_id_by_key[key] ||= begin
      new_id = @bus_routes.size + 1
      @bus_routes << attrs.merge(id: new_id, created_at: @now, updated_at: @now)
      new_id
    end
  end

  # ---------------------------------------------------------------------------
  # 2. バス停 XML のパース（BusStop / BusRouteInformation）
  # ---------------------------------------------------------------------------

  # バス停 XML 側は「種別 + 会社 + 路線名」だけで路線を引きたい。
  # 運賃や備考まで揃わないので、route_id_by_key（7 要素キー）はそのままでは引けず、
  # 3 要素キーの逆引きインデックスをここで作っておく。
  #
  # 同一 (種別, 会社, 路線名) が運賃や区間 (note) 違いで複数 BusRoute に分かれているケースが
  # ある (例: 神奈中の「津01」が長津田駅〜長津田辻 と 奈良井〜奈良井の 2 系統)。バス停 XML 側は
  # 3 要素しか持たないので、すべての候補 route_id を保持しておき link_stop_to_routes で
  # 「バス停の座標に最も近い route」を選ぶ。@coords_by_route_id は最近接判定の入力。
  def build_route_lookup
    @route_lookup = @bus_routes.each_with_object({}) do |route, lookup|
      key = [ route[:bus_type], route[:operation_company], route[:line_name] ]
      lookup[key] ||= []
      lookup[key] << route[:id]
    end

    @coords_by_route_id = Hash.new { |h, k| h[k] = [] }
    @bus_route_tracks.each do |track|
      next unless track[:bus_route_id]
      @coords_by_route_id[track[:bus_route_id]].concat(@track_coords_by_id[track[:id]] || [])
    end
  end

  def parse_stop_xml(code, prefecture)
    xml_path = STOP_XML_FORMAT % code
    doc = open_xml(xml_path)
    pos_hash = build_position_index(doc)

    nodes = doc.css("BusStop")
    nodes.each do |node|
      bs_id = create_bus_stop(node, pos_hash, prefecture)
      link_stop_to_routes(node, bs_id)
    end
    puts "  Stops #{code}: #{nodes.size} stops"
  end

  # Point 要素の id → 緯度経度文字列の対応表。
  # BusStop の position[href] でこの id を引いて座標を取得する。
  def build_position_index(doc)
    doc.css("Point").each_with_object({}) { |n, h| h[n["id"]] = n.at("pos").text }
  end

  def create_bus_stop(node, pos_hash, prefecture)
    href = node.at("position")["href"].remove("#")
    pos  = pos_hash[href]

    bs_id = @bus_stops.size + 1
    @bus_stops << {
      id: bs_id,
      gml_id: node["id"],
      name: node.at("busStopName").text,
      latitude:  pos.split[0].to_f,
      longitude: pos.split[1].to_f,
      created_at: @now,
      updated_at: @now,
      # prefecture は P11 XML から、city / formatted_address は geocode:generate (ISJ)、
      # keyword は keyword:generate (kakasi) で別途埋まる。
      prefecture: prefecture,
      city: nil,
      formatted_address: nil,
      keyword: nil
    }
    bs_id
  end

  # 1 つの BusStop に複数の路線が紐づく（中間テーブル bus_route_bus_stops に展開）。
  # 同一 3 要素キーに複数 BusRoute がぶら下がる場合は、バス停の座標に最も近い軌跡を持つ
  # BusRoute を選ぶ。これがないと最初に登録された 1 件にすべてのバス停が吸われる。
  def link_stop_to_routes(node, bs_id)
    bs = @bus_stops[bs_id - 1]
    lat = bs[:latitude]
    lng = bs[:longitude]

    node.css("BusRouteInformation").each do |info|
      key = [
        info.at("busType").text.to_i,
        info.at("busOperationCompany").text,
        info.at("busLineName").text
      ]
      candidates = @route_lookup[key]
      next if candidates.nil? || candidates.empty?

      route_id = pick_nearest_route(candidates, lat, lng)

      @bus_route_bus_stops << {
        id: @bus_route_bus_stops.size + 1,
        bus_route_id: route_id,
        bus_stop_id: bs_id,
        bus_stop_number: nil, # bus_stop_number:load が CSV から埋める
        created_at: @now,
        updated_at: @now
      }
    end
  end

  # 候補の BusRoute から、軌跡の最近接 coord までの距離が最小の 1 つを選ぶ。
  # squared euclidean (lat, lng の度差²乗合算) で十分。track が紐付いていない BusRoute は
  # 距離 INF 扱いで実質的に最後の候補になる。
  def pick_nearest_route(candidates, lat, lng)
    return candidates.first if candidates.size == 1
    candidates.min_by do |route_id|
      coords = @coords_by_route_id[route_id]
      if coords.empty?
        Float::INFINITY
      else
        coords.map { |c| (lat - c[0]) ** 2 + (lng - c[1]) ** 2 }.min
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 3. CSV 書き出し（PostgreSQL の COPY FROM ... CSV HEADER 互換フォーマット）
  # ---------------------------------------------------------------------------

  def write_all_csv
    data_dir = Rails.root.join("db/data")
    data_dir.mkpath

    write_csv(data_dir, "bus_routes", @bus_routes,
              %w[id bus_type operation_company line_name weekday_rate saturday_rate holiday_rate note created_at updated_at])
    write_csv(data_dir, "bus_route_tracks", @bus_route_tracks,
              %w[id gml_id coordinates bus_route_id created_at updated_at])
    write_csv(data_dir, "bus_stops", @bus_stops,
              %w[id gml_id name latitude longitude created_at updated_at prefecture city formatted_address keyword])
    write_csv(data_dir, "bus_route_bus_stops", @bus_route_bus_stops,
              %w[id bus_route_id bus_stop_id bus_stop_number created_at updated_at])
  end

  def write_csv(dir, name, rows, columns)
    path = dir.join("#{name}.csv")
    CSV.open(path, "w", headers: columns, write_headers: true) do |csv|
      rows.each { |row| csv << columns.map { |c| row[c.to_sym] } }
    end
    puts "Wrote #{path} (#{rows.size} rows)"
  end

  # ---------------------------------------------------------------------------
  # ヘルパ
  # ---------------------------------------------------------------------------

  def open_xml(path)
    io = path.to_s.end_with?(".gz") ? Zlib::GzipReader.open(path) : File.open(path)
    doc = Nokogiri::XML(io)
    io.close
    doc.remove_namespaces! # 名前空間を全部剥がして css セレクタを使いやすくする
    doc
  end

  # "lat lng\nlat lng\n..." → [{x:, y:}, ...] のハッシュ配列に変換（SimplifyRb 用）
  def parse_coordinates(text)
    text.strip.each_line.map do |line|
      x, y = line.split
      { x: x.to_f, y: y.to_f }
    end
  end

  # SimplifyRb で頂点を間引いた後、[[x, y], ...] の配列に戻す。
  def simplify_coordinates(coords)
    SimplifyRb::Simplifier.new.process(coords, 0.0001).map { |c| [ c[:x], c[:y] ] }
  end

  # JSON gem の Float#to_json は 17 桁出すため、Float#to_s（最短ラウンドトリップ）を使う。
  # 文字列補間は内部で to_s を呼ぶので、この書き方で十分短くなる。
  def coordinates_to_compact_json(simplified)
    "[" + simplified.map { |x, y| "[#{x},#{y}]" }.join(",") + "]"
  end
end

namespace :data do
  # COPY 文の対象テーブル。順序は外部キー依存順（先に親、最後に子）。
  TABLES = %w[bus_routes bus_route_tracks bus_stops bus_route_bus_stops].freeze

  desc "Profile data:generate via stackprof (writes tmp/data_generate.stackprof)"
  task profile: :environment do
    require "nokogiri"
    require "simplify_rb"
    require "csv"
    require "zlib"
    require "stackprof"

    $stdout.sync = true
    out = "tmp/data_generate.stackprof"
    StackProf.run(mode: :wall, out: out, interval: 1000) do
      DataGenerator.new.run
    end
    puts ""
    puts "Profile saved to #{out}"
    puts "View top by self time:   bundle exec stackprof #{out} --text --limit 30"
    puts "View top by total time:  bundle exec stackprof #{out} --text --total --limit 30"
  end

  desc "Generate db/data/*.csv from XML sources"
  task generate: :environment do
    require "nokogiri"
    require "simplify_rb"
    require "csv"
    require "zlib"

    $stdout.sync = true
    DataGenerator.new.run
  end

  desc "Load db/data/*.csv into the database (TRUNCATE + COPY FROM STDIN)"
  task load: :environment do
    raw = ActiveRecord::Base.connection.raw_connection

    ActiveRecord::Base.transaction do
      # まとめて TRUNCATE。RESTART IDENTITY で sequence もリセットし、
      # CASCADE で外部キー参照側も連鎖して空にする。
      raw.exec("TRUNCATE TABLE #{TABLES.join(', ')} RESTART IDENTITY CASCADE")

      TABLES.each do |table|
        path = Rails.root.join("db/data/#{table}.csv")
        raise "Missing #{path}. Run 'rails data:generate' first." unless path.exist?

        # CSV のヘッダ行を読み、列順を COPY 文に明示する。
        # COPY ... CSV HEADER はヘッダを読み飛ばすだけで列マッピングをしないため、
        # CSV と DB の物理カラム順が異なる環境（schema:load 由来など）で壊れる。
        columns = File.open(path, "r") { |f| f.readline.chomp.split(",") }

        raw.copy_data("COPY #{table} (#{columns.join(', ')}) FROM STDIN WITH CSV HEADER") do
          File.open(path, "r") do |f|
            while (line = f.gets)
              raw.put_copy_data(line)
            end
          end
        end

        # COPY は sequence を進めないため、MAX(id) + 1 にリセットしておく。
        # これをしないと、後で AR から create したときに id 衝突が起きる。
        raw.exec("SELECT setval(pg_get_serial_sequence('#{table}', 'id'), COALESCE(MAX(id), 0) + 1, false) FROM #{table}")
        puts "Loaded #{path}"
      end
    end
  end
end
