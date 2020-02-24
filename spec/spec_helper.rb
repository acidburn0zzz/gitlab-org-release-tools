# frozen_string_literal: true

# This ensures we don't push to the repo during tests
ENV['TEST'] = 'true'

# Don't let production feature flags affect a test run
ENV.delete('FEATURE_INSTANCE_ID')

# Stub API tokens
ENV['OPS_API_PRIVATE_TOKEN'] = 'test'
ENV['RELEASE_BOT_DEV_TOKEN'] = 'test'
ENV['RELEASE_BOT_PRODUCTION_TOKEN'] = 'test'
ENV['VERSION_API_PRIVATE_TOKEN'] = 'test'

# SimpleCov needs to be loaded before everything else
require_relative 'support/simplecov'

require_relative '../lib/release_tools'
require 'active_support/core_ext/string/strip'
require 'active_support/core_ext/object/inclusion'

Dir[File.expand_path('support/**/*.rb', __dir__)].each { |f| require f }

RSpec.configure do |config|
  config.run_all_when_everything_filtered = true
  config.filter_run :focus
  config.order = 'random'

  unless ENV['CI']
    config.example_status_persistence_file_path = './spec/examples.txt'
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.around do |ex|
    # HACK (rspeicher): Work around a transient timing failure when the user has
    # a Git template dir (such as ~/.git_template)
    ClimateControl.modify(GIT_TEMPLATE_DIR: '') do
      ex.run
    end
  end
end
