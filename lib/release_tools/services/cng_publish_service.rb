# frozen_string_literal: true

module ReleaseTools
  module Services
    class CNGPublishService < BasePublishService
      include ReleaseTools::Support::UbiHelper

      def play_stages
        @play_stages ||= %w[release].freeze
      end

      def release_versions
        @release_versions ||= [
          @version.to_ce.tag,
          @version.to_ee.tag,
          ubi_tag(@version.to_ee)
        ]
      end

      def project
        @project ||= Project::CNGImage
      end
    end
  end
end
