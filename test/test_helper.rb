require "simplecov"
SimpleCov.start "rails"

require "minitest/mock"

ENV["RAILS_ENV"] ||= "test"
require File.expand_path("../../config/environment", __FILE__)
require "rails/test_help"

Geocoder.configure(lookup: :test)

# GooglePlaces API レスポンスのスタブで使う最小限の Spot 値オブジェクト。
# nil への singleton メソッド定義のような副作用のあるパターンを避けるために用意。
GooglePlacesSpot = Struct.new(:place_id, :name, :lat, :lng, :formatted_address, keyword_init: true)

class ActiveSupport::TestCase
  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # `GooglePlaces::Client` を一時的にモックに差し替えるブロックヘルパー。
  # `remove_const` を直接書くと差し替えが残って後続テストを汚染するため、
  # ensure で必ず元の定数を復元する。
  #
  # `Client.new` はコントローラの cache 判定の前に毎回呼ばれるため、HTTP リクエストの
  # 回数だけインスタンス化されうる。検証したいのは `spots_by_query` の呼び出しなので、
  # `new` は何度呼ばれても同じ instance_mock を返す class double で受ける。
  def with_google_places_stub(spots:)
    instance_mock = Minitest::Mock.new
    instance_mock.expect :spots_by_query, spots, [ String ], lat: Float, lng: Float, radius: Integer, language: String

    class_double = Object.new
    class_double.define_singleton_method(:new) { |_api_key| instance_mock }

    original = GooglePlaces::Client
    GooglePlaces.send(:remove_const, :Client)
    GooglePlaces.const_set(:Client, class_double)
    begin
      yield
      instance_mock.verify
    ensure
      GooglePlaces.send(:remove_const, :Client)
      GooglePlaces.const_set(:Client, original)
    end
  end
end
