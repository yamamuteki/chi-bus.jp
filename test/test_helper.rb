require 'coveralls'
Coveralls.wear!

require 'simplecov'
SimpleCov.start 'rails'

require "minitest/reporters"
require "minitest/mock"
Minitest::Reporters.use!

ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'

Geocoder.configure(lookup: :test)

class ActiveSupport::TestCase
  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Add more helper methods to be used by all tests here...
end
