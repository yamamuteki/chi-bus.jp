ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require 'bundler/setup' # Set up gems listed in the Gemfile.
require 'logger' # Workaround for Rails 6.0.6 autoload issue, removable after upgrading to 6.1
require 'bootsnap/setup' # Speed up boot time by caching expensive operations.
