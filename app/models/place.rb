class Place
  extend Forwardable

  def_delegators :@spot, :name, :formatted_address
  def_delegator :@spot, :place_id, :id
  def_delegator :@spot, :lat, :latitude
  def_delegator :@spot, :lng, :longitude

  def initialize(spot)
    @spot = spot
  end

  def spot
    @spot
  end
end
