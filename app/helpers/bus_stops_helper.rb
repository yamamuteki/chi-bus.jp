module BusStopsHelper
  def bus_stop_or_place_path(bus_stop)
    if bus_stop.is_a? Place then
      "#{bus_stops_path}?position=#{bus_stop.latitude},#{bus_stop.longitude}"
    else
      bus_stop_path bus_stop
    end
  end

  def bus_stop_badge(bus_stop)
    if bus_stop.is_a? Place then
      '周辺'
    else
      bus_stop.bus_routes.size
    end
  end
end
