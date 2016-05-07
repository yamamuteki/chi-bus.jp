class BusRoute < ActiveRecord::Base
  has_many :bus_route_tracks
  has_many :bus_route_bus_stops, -> { order(:bus_stop_number) }
  has_many :bus_stops, through: :bus_route_bus_stops

  enum bus_type: { private_bus: 1, public_bus: 2, community_bus: 3, demand_bus: 4, other: 5 }

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
