require "test_helper"

# DB を使わない PORO の単体テスト。fixtures をスキップするため Minitest::Test を直接継承。
class IsjReverseGeocoderTest < Minitest::Test
  def entry(prefecture, city, place, lat, lng)
    IsjReverseGeocoder::Entry.new(
      prefecture: prefecture,
      city: city,
      place: place,
      latitude: lat,
      longitude: lng
    )
  end

  def test_empty_entries_returns_nil
    geocoder = IsjReverseGeocoder.new([])
    assert_nil geocoder.reverse_geocode(35.0, 140.0)
  end

  def test_single_entry_in_same_bucket_is_returned
    e = entry("千葉県", "千葉市", "中央区", 35.6049, 140.1208)
    geocoder = IsjReverseGeocoder.new([ e ])
    result = geocoder.reverse_geocode(35.6050, 140.1210)
    assert_equal e, result
  end

  def test_returns_nearest_among_multiple_entries
    near = entry("千葉県", "千葉市", "中央区", 35.6049, 140.1208)
    far  = entry("千葉県", "千葉市", "美浜区", 35.6489, 140.0337)
    geocoder = IsjReverseGeocoder.new([ near, far ])
    result = geocoder.reverse_geocode(35.6050, 140.1210)
    assert_equal near, result
  end

  def test_falls_back_to_wider_radius_when_no_entry_in_immediate_bucket
    # 9 bucket (3x3 = 0.03°) 内に 1 件もない場合、radius を拡張して見つける。
    # entry を 0.05° (~5km) 離した場所に置く。1 bucket (0.01°) では届かないが
    # radius=5 (0.05°) で届く。
    far_but_only = entry("千葉県", "千葉市", "中央区", 35.5, 140.1)
    geocoder = IsjReverseGeocoder.new([ far_but_only ])
    result = geocoder.reverse_geocode(35.55, 140.15)
    assert_equal far_but_only, result
  end

  def test_format_address_concatenates_prefecture_city_place
    e = entry("千葉県", "千葉市中央区", "青葉町", 35.5972, 140.1399)
    assert_equal "千葉県千葉市中央区青葉町", IsjReverseGeocoder.format_address(e)
  end

  def test_picks_nearest_across_bucket_boundaries
    # 同じ地点近くに 2 件 (異なる bucket): 0.005° 離れた "near" と 0.02° 離れた "far"。
    # 中点付近 (0.011°) で検索したとき近い方が返される。
    near = entry("千葉県", "市原市", "近", 35.605, 140.121)
    far  = entry("千葉県", "市原市", "遠", 35.620, 140.121)
    geocoder = IsjReverseGeocoder.new([ near, far ])
    result = geocoder.reverse_geocode(35.610, 140.121)
    assert_equal near, result
  end
end
