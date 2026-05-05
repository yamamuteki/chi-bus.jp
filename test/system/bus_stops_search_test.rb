require "application_system_test_case"

class BusStopsSearchTest < ApplicationSystemTestCase
  test "should show matching bus stops when searching by keyword" do
    visit root_path

    # `#q` はメニューにも存在するためトップページのフォームに限定する。
    within ".home-parent form" do
      fill_in "q", with: "Stop"
      find("button[type=submit]").click
    end

    assert_selector "a.list-group-item", count: 2
  end

  test "should follow link from list to bus stop detail" do
    Geocoder::Lookup::Test.add_stub(
      "1.5,1.5", [
        {
          "latitude"     => 40.7143528,
          "longitude"    => -74.0059731,
          "address"      => "New York, NY, USA",
          "state"        => "New York",
          "state_code"   => "NY",
          "country"      => "United States",
          "country_code" => "US"
        }
      ]
    )

    visit bus_stops_path(q: "Stop")
    first("a.list-group-item").click

    assert_selector "h3", text: /BusStop/
  end
end
