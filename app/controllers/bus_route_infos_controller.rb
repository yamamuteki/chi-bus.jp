class BusRouteInfosController < ApplicationController
  def show
    @bus_route_info = BusRouteInfo.find(params[:id])
  end
end
