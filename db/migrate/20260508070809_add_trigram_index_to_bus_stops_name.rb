class AddTrigramIndexToBusStopsName < ActiveRecord::Migration[8.1]
  # `keyword` が空 (= keyword:load 未実行 / kakasi 失敗) の停留所を救済するため、検索クエリで
  # `name ILIKE` を OR 条件に加える。`name` 側にも GIN trigram index を張り、3 文字以上の
  # 検索なら BitmapOr で両 index を結合して同等速度 (~0.3ms) を維持する。
  def change
    add_index :bus_stops, :name, using: :gin, opclass: :gin_trgm_ops
  end
end
