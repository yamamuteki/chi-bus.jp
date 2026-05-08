class AddTrigramIndexToBusStopsKeyword < ActiveRecord::Migration[8.1]
  # PostgreSQL の B-tree インデックスは LIKE '%xxx%' (substring) を高速化できない。
  # pg_trgm 拡張 + GIN trigram インデックスで部分一致検索を高速化する。
  # 全国対応で bus_stops が 254,842 件まで増え、現状の Seq Scan で ~900ms かかっていた。
  def change
    enable_extension :pg_trgm
    add_index :bus_stops, :keyword, using: :gin, opclass: :gin_trgm_ops
  end
end
