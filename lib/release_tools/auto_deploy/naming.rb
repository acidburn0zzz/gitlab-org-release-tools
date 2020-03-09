# frozen_string_literal: true

module ReleaseTools
  module AutoDeploy
    class Naming
      BRANCH_FORMAT = '%<major>d-%<minor>d-auto-deploy-%<timestamp>s'

      def self.branch
        new.branch
      end

      def branch
        format(
          BRANCH_FORMAT,
          major: version.first,
          minor: version.last,
          timestamp: Time.now.strftime('%Y%m%d')
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
