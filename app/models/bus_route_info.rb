class BusRouteInfo < ActiveRecord::Base
  has_and_belongs_to_many :bus_stops, -> { order('name, latitude DESC') }
  has_one :bus_route

  enum bus_type: { private_bus: 1, public_bus: 2, community_bus: 3, demand_bus: 4, other: 5 }

  BUS_TYPE_LABELS = {
    private_bus: "路線バス（民間）",
    public_bus: "路線バス（公営）",
    community_bus: "コミュニティバス",
    demand_bus: "デマンドバス",
    other: "その他"
  }

  def bus_type_label
    BUS_TYPE_LABELS[bus_type.to_sym]
  end
end
