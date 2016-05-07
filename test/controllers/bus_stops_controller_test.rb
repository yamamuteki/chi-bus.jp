require 'test_helper'

class BusStopsControllerTest < ActionController::TestCase
  test "should get index" do
    get :index
    assert_response :success
  end

  test "should get show" do
    Geocoder::Lookup::Test.add_stub(
      "1.5,1.5", [
        {
          'latitude'     => 40.7143528,
          'longitude'    => -74.0059731,
          'address'      => 'New York, NY, USA',
          'state'        => 'New York',
          'state_code'   => 'NY',
          'country'      => 'United States',
          'country_code' => 'US'
        }
      ]
    )

    get :show, { id: bus_stops(:one) }
    assert_response :success
  end

end
