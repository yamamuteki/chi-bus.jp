class BusStopsController < ApplicationController
  def index
    @bus_stops = BusStop.where("name like '%#{params[:q]}%'").limit(100)
  end

  def show
    @bus_stop = BusStop.find(params[:id])
  end
end
