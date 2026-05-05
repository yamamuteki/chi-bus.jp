require "application_system_test_case"

class HomeTest < ApplicationSystemTestCase
  test "should show logo, lead text, and search form" do
    visit root_path

    assert_selector "h1", text: "chi-bus.jp"
    assert_selector "p.lead"
    assert_selector ".home-parent form input#q"
  end
end
