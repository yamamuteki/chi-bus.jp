class RemovePostalCodeFromBusStops < ActiveRecord::Migration[8.1]
  # postal_code は Google Geocoding API 連携時の旧データで、UI / 検索のいずれにも
  # 使われていなかった。reverse geocoding を ISJ (位置参照情報) ベースに切り替えて
  # 以降は populate されないため、列ごと削除する。
  def change
    remove_column :bus_stops, :postal_code, :string
  end
end
