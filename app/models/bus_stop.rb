class BusStop < ApplicationRecord
  has_many :bus_route_bus_stops
  has_many :bus_routes, -> { order("operation_company, line_name") }, through: :bus_route_bus_stops

  # 距離検索 (`BusStop.near([lat, lng], km)`) は geocoder gem の `near` スコープを使う。
  # reverse_geocoded_by は緯度経度カラム名を gem に伝えるための宣言。block は不要。
  # 旧実装の block 内 (Google API 結果から住所列をセット) は geocode:generate
  # (ISJ オフライン処理) に置き換えた。
  reverse_geocoded_by :latitude, :longitude

  def address
    formatted_address
  end

  def formatted_address
    self[:formatted_address].to_s
  end
end
