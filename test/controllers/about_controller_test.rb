require "test_helper"

class AboutControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get about_path
    assert_response :success
  end

  test "should render service description sections" do
    get about_path
    assert_select "h2", text: "chi-bus.jpについて"
    assert_select ".panel-heading", text: "このサービスは何ですか？"
  end
end
