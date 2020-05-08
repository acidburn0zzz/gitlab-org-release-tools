# frozen_string_literal: true

require 'http'

module ReleaseTools
  module Deployments
    # Tracking Sentry releases
    class SentryTracker
      API_ENDPOINT = 'https://sentry.gitlab.net/api/0/organizations/gitlab/releases/'
      REPOSITORY = 'GitLab.org / security / 🔒 gitlab'
      PROJECTS = %w[gitlabcom staginggitlabcom].freeze

      def initialize(sha)
        @sha = sha
        @token = ENV.fetch('SENTRY_AUTH_TOKEN') do |name|
          raise "Missing environment variable `#{name}`"
        end
      end

      def execute
        HTTP.auth(auth_token)
          .post(
            API_ENDPOINT,
            json: parameters
          )
      end

      private

      def auth_token
        "Bearer #{@token}"
      end

      def version
        @sha[0...11]
      end

      def parameters
        {
          version: version,
          refs: [
            {
              repository: REPOSITORY,
              commit: @sha
            }
          ],
          projects: PROJECTS
        }
      end
    end
  end
end
