require "csv"

# 国土交通省 位置参照情報 (Isj, 大字・町丁目レベル, 18.0b/令和6年版) を使った
# オフライン reverse geocoder。
#
# bus_stop の (lat, lng) から最近接の大字・町丁目エントリを引き、(都道府県, 市区町村,
# 大字町丁目名) を返す。Google Reverse Geocoding API 等の外部依存を排除し高速化する。
#
# データ取得: db/isj/{prefcode}-18.0b/*.csv (Shift_JIS, 計約 19 万 entries 全国分)。
# 詳しいソース: https://nlftp.mlit.go.jp/cgi-bin/isj/dls/_choose_method.cgi
#
# 探索方式: lat/lng を GRID_SIZE 単位で bucket 化したハッシュに登録し、対象点の周囲
# (3x3 = 9 bucket) を scan して最小距離を返す。1 件もヒットしない場合は探索半径を拡張。
class IsjReverseGeocoder
  Entry = Struct.new(:prefecture, :city, :place, :latitude, :longitude, keyword_init: true)

  # 緯度経度の bucket サイズ (deg)。0.01° ≒ 約 1km。1 都道府県あたり ~4000 entries で
  # bucket 数 ~10000 → 1 bucket ~0.4 entries。bus_stop あたり 9 bucket = ~4 件比較で
  # 14 万 bus_stops 全件処理が数秒で終わる。
  GRID_SIZE = 0.01

  # ヒットしないときに段階的に拡張する半径 (bucket 単位)。最大 50 → 約 50km。
  # 離島・山奥バス停も最寄り集落でカバーする想定。
  FALLBACK_RADII = [ 1, 5, 20, 50 ].freeze

  # `db/isj/*-18.0b/*.csv` 一括ロード。
  def self.from_directory(dir)
    entries = load_entries(dir)
    new(entries)
  end

  def self.load_entries(dir)
    entries = []
    Dir.glob(File.join(dir, "*-18.0b", "*.csv")).each do |path|
      # ISJ CSV は CP932 (Windows 拡張 Shift_JIS)、ヘッダ行付き。
      # 「髙」等の機種依存文字含むため Shift_JIS だと UndefinedConversionError、CP932 で読む。
      CSV.foreach(path, encoding: "CP932:UTF-8", headers: true) do |row|
        lat = row["緯度"]&.to_f
        lng = row["経度"]&.to_f
        next if lat.nil? || lng.nil? || lat.zero? || lng.zero?
        entries << Entry.new(
          prefecture: row["都道府県名"],
          city: row["市区町村名"],
          place: row["大字町丁目名"],
          latitude: lat,
          longitude: lng
        )
      end
    end
    entries
  end

  def initialize(entries)
    @entries = entries
    @grid = Hash.new { |h, k| h[k] = [] }
    @entries.each do |e|
      @grid[bucket_key(e.latitude, e.longitude)] << e
    end
  end

  # 最近接 entry を返す。ヒットしない場合 nil。
  def reverse_geocode(lat, lng)
    blat = (lat / GRID_SIZE).floor
    blng = (lng / GRID_SIZE).floor

    FALLBACK_RADII.each do |radius|
      candidates = []
      (-radius..radius).each do |dlat|
        (-radius..radius).each do |dlng|
          bucket = @grid[[ blat + dlat, blng + dlng ]]
          candidates.concat(bucket) unless bucket.empty?
        end
      end
      next if candidates.empty?

      best = candidates.min_by { |e| (lat - e.latitude) ** 2 + (lng - e.longitude) ** 2 }
      return best
    end
    nil
  end

  # `formatted_address` は「都道府県名 + 市区町村名 + 大字町丁目名」を連結。
  def self.format_address(entry)
    "#{entry.prefecture}#{entry.city}#{entry.place}"
  end

  private

  def bucket_key(lat, lng)
    [ (lat / GRID_SIZE).floor, (lng / GRID_SIZE).floor ]
  end
end
