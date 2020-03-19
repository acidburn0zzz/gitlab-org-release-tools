# frozen_string_literal: true

module ReleaseTools
  module Services
    class OmnibusPublishService < BasePublishService
      def play_stages
        @play_stages ||= %w[
          package-and-image-release
          raspbian-release
          metrics
        ].freeze
      end

      def release_versions
        @release_versions ||= [@version.to_omnibus(ee: false), @version.to_omnibus(ee: true)]
      end

      def project
        @project ||= Project::OmnibusGitlab
      end
    end
  end
end
