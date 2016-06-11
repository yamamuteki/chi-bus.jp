require 'test_helper'

class BusStopTest < ActiveSupport::TestCase
  test "should new" do
    assert BusStop.new
  end

  test "should have attributes" do
    bus_stop = BusStop.new
    assert_respond_to bus_stop, :gml_id
    assert_respond_to bus_stop, :name
    assert_respond_to bus_stop, :latitude
    assert_respond_to bus_stop, :longitude
    assert_respond_to bus_stop, :bus_route_bus_stops
    assert_respond_to bus_stop, :bus_routes
    assert_respond_to bus_stop, :address
    assert_respond_to bus_stop, :formatted_address
  end

  test "should address return address" do
    bus_stop = BusStop.new(formatted_address: 'New York, NY, USA')
    assert_equal 'New York, NY, USA', bus_stop.address
  end

  test "should formatted_address return ''" do
    assert_equal '', BusStop.new.formatted_address
  end

  test "should bus_routes order by operation_company, line_name" do
    bus_stop = BusStop.new
    bus_stop.bus_route_bus_stops << BusRouteBusStop.new(bus_route: BusRoute.new(operation_company: '2', line_name: '2'))
    bus_stop.bus_route_bus_stops << BusRouteBusStop.new(bus_route: BusRoute.new(operation_company: '2', line_name: '1'))
    bus_stop.bus_route_bus_stops << BusRouteBusStop.new(bus_route: BusRoute.new(operation_company: '1', line_name: '2'))
    bus_stop.bus_route_bus_stops << BusRouteBusStop.new(bus_route: BusRoute.new(operation_company: '1', line_name: '1'))
    bus_stop.save

    bus_stop.reload
    assert_equal '1', bus_stop.bus_routes[0].operation_company
    assert_equal '1', bus_stop.bus_routes[0].line_name
    assert_equal '1', bus_stop.bus_routes[1].operation_company
    assert_equal '2', bus_stop.bus_routes[1].line_name
    assert_equal '2', bus_stop.bus_routes[2].operation_company
    assert_equal '1', bus_stop.bus_routes[2].line_name
    assert_equal '2', bus_stop.bus_routes[3].operation_company
    assert_equal '2', bus_stop.bus_routes[3].line_name
  end

  test "should reverse_geocode set attributes" do
    Geocoder::Lookup::Test.add_stub(
      [40.7143528, -74.0059731], [
        {
          'postal_code' => '000-0000',
          'formatted_address' => '日本, Test Address'
        }
      ]
    )

    class Geocoder::Result::Test
      def address_components
        [{ 'types' => ['locality', 'political'], 'long_name' => 'City Name' }]
      end
    end

    bus_stop = BusStop.new(latitude: 40.7143528, longitude:-74.0059731)
    bus_stop.reverse_geocode

    assert_equal '000-0000', bus_stop.postal_code
    assert_equal 'City Name', bus_stop.city
    assert_equal 'Test Address', bus_stop.formatted_address
  end
end
