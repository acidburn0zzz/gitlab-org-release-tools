# frozen_string_literal: true

module ReleaseTools
  module AutoDeploy
    class Naming
      BRANCH_FORMAT = '%<major>d-%<minor>d-auto-deploy-%<timestamp>s'
      TAG_FORMAT = '%<major>d.%<minor>d.%<timestamp>s+%<ee_ref>.11s.%<packager_ref>.11s'

      def self.branch
        new.branch
      end

      def self.tag(timestamp:, packager_ref:, ee_ref:)
        new.tag(
          timestamp: timestamp,
          packager_ref: packager_ref,
          ee_ref: ee_ref
        )
      end

      def branch
        format(
          BRANCH_FORMAT,
          major: version.first,
          minor: version.last,
          timestamp: Time.now.strftime('%Y%m%d')
        )
      end

      def tag(timestamp:, packager_ref:, ee_ref:)
        format(
          TAG_FORMAT,
          major: version.first,
          minor: version.last,
          timestamp: Time.parse(timestamp).strftime('%Y%m%d%H%M'),
          packager_ref: packager_ref,
          ee_ref: ee_ref
        )
      end

      def version
        @version ||=
          begin
            milestone = ReleaseTools::GitlabClient
              .current_milestone
              .title

            unless milestone.match?(/\A\d+\.\d+\z/)
              raise ArgumentError, "Invalid version from milestone: #{milestone}"
            end

            milestone.split('.')
          end
      end
    end
  end
end
