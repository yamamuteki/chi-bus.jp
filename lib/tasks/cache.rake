# encoding: utf-8
require File.expand_path(File.dirname(__FILE__) + "/../../config/environment")

namespace :cache do
  desc 'Clear Rails cache'
  task :clear => :environment do
    Rails.cache.clear
  end
end

