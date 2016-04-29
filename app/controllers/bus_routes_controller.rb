class BusRoutesController < ApplicationController
  def show
    # Don't use preload for keeping bus stop order (Use fragment cache)
    @bus_route = BusRoute.find(params[:id])
  end
end
