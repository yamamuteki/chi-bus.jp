class Place
  extend Forwardable

  def_delegators :@spot, :name
  def_delegator :@spot, :place_id, :id
  def_delegator :@spot, :lat, :latitude
  def_delegator :@spot, :lng, :longitude

  def initialize(spot)
    @spot = spot
  end

  def formatted_address
    @spot.formatted_address.delete('日本, ')
  end

  def city
    nil
  end

  def spot
    @spot
  end
end
