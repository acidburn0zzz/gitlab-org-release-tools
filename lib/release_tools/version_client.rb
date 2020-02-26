# frozen_string_literal: true

require 'gitlab/request'

module ReleaseTools
  # Client for the version.gitlab.com API
  #
  # Because the API so closely resembles the API of GitLab CE/EE, we're able to
  # repurpose the gitlab gem's `Gitlab::Request` class to get automatic error
  # handling and response parsing.
  class VersionClient < Gitlab::Request
    base_uri 'https://version.gitlab.com'
    headers 'Private-Token' => -> { api_token }

    # Get the latest version information
    #
    # Returns an Array of Gitlab::ObjectifiedHash objects
    def self.versions
      get('/api/v1/versions', query: { per_page: 50 })
    end

    def self.api_token
      ENV.fetch('RELEASE_BOT_VERSION_TOKEN') do |name|
        raise "Must specify `#{name}` environment variable!"
      end
    end

    private_class_method :api_token
  end
end
