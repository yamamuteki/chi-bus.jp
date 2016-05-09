# Set the host name for URL creation
SitemapGenerator::Sitemap.default_host = "https://www.chi-bus.jp"

SitemapGenerator::Sitemap.create do
  add root_path, :priority => 0.7, :changefreq => 'weekly'
  add about_path, :priority => 0.7, :changefreq => 'weekly'

  BusStop.find_each do |bus_stop|
    add bus_stop_path(bus_stop), lastmod: bus_stop.updated_at
  end

  BusRoute.find_each do |bus_route|
    add bus_route_path(bus_route), lastmod: bus_route.updated_at
  end
end
