require 'test_helper'

class BusRoutesControllerTest < ActionController::TestCase
  test "should get show" do
    get :show, { id: bus_routes(:one) }
    assert_response :success
  end

end
