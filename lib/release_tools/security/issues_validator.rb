# frozen_string_literal: true

module ReleaseTools
  module Security
    # Validating issuess associated to the Security Release Tracking Issue
    class IssuesValidator
      include ::SemanticLogger::Loggable

      def initialize(client)
        @client = client
        @ready = []
        @not_ready = []
      end

      def execute
        logger.info("#{security_issues.count} associated to the Security Release Tracking issue.")

        security_issues.each do |security_issue|
          if security_issue.ready_to_be_processed?
            @ready << security_issue
          else
            @not_ready << security_issue
          end
        end

        display_issues_result

        @ready
      end

      private

      def security_issues
        @security_issues ||=
          Security::IssueCrawler
            .new
            .upcoming_security_issues_and_merge_requests
      end

      def display_issues_result
        issues_result = IssuesResult.new(security_issues, @ready, @not_ready)

        Slack::ChatopsNotification.security_issues_processed(issues_result)

        return if @not_ready.empty?

        logger.info('Security implementation issues not ready to be processed:')

        @not_ready.each do |issue|
          logger.warn(issue.web_url)
        end
      end
    end
  end
end
