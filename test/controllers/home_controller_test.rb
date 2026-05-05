require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get root_path
    assert_response :success
  end

  test "should render logo and search form" do
    get root_path
    assert_select "h1", text: /chi-bus\.jp/
    assert_select ".home-parent form input#q"
  end
end
