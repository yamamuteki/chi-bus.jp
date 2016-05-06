require 'test_helper'

class BusStopsControllerTest < ActionController::TestCase
  test "should get index" do
    get :index
    assert_response :success
  end

  test "should get show" do
    get :show, { id: bus_stops(:one) }
    assert_response :success
  end

end
