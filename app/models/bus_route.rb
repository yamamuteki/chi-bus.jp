class BusRoute < ApplicationRecord
  has_many :bus_route_tracks
  has_many :bus_route_bus_stops, -> { order(:bus_stop_number) }
  has_many :bus_stops, through: :bus_route_bus_stops

  enum :bus_type, { private_bus: 1, public_bus: 2, community_bus: 3, demand_bus: 4, other: 5 }

  # `fragmented = true` は data:generate 時に「N07 上で 1 路線として表現できない」と
  # 判定された route。一覧/検索からは除外し、直接 URL アクセス時のみ alert 付きで表示する。
  # 判定基準は data.rake の `mark_fragmented_routes` 参照。
  #
  # default_scope で除外することで「呼び出し側が忘れたら fragmented が漏れる」事故を防ぐ。
  # 含めたい場合は明示的に `BusRoute.with_fragmented` を使う:
  #   - bus_routes/show: 直接 URL アクセス対応で必要
  #   - bus_stop_number:generate: fragmented route にも採番する
  #   - bus_stop_number:diagnose: INCLUDE_FRAGMENTED=1 のとき
  default_scope { where(fragmented: false) }
  scope :with_fragmented, -> { unscope(where: :fragmented) }
  scope :fragmented_only, -> { unscope(where: :fragmented).where(fragmented: true) }

  BUS_TYPE_LABELS = {
    private_bus: "路線バス（民間）",
    public_bus: "路線バス（公営）",
    community_bus: "コミュニティバス",
    demand_bus: "デマンドバス",
    other: "その他"
  }

  def bus_type_label
    BUS_TYPE_LABELS[bus_type.to_s.to_sym]
  end
end
