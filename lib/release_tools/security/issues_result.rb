# frozen_string_literal: true

module ReleaseTools
  module Security
    class IssuesResult
      attr_reader :total, :pending, :invalid

      def initialize
        @total = []
        @not_ready = []
        @ready = []
      end

      def slack_attachments
        [
          total_issues,
          not_ready,
          ready
        ]
      end

      private

      def total_issues
        {
          fallback: "Total of Security Implementation Issues associated: #{total.length}.",
          title: ":information_source: Total: #{total.length}.",
          color: 'good'
        }
      end

      def not_ready
        return {} if not_ready.empty?

        {
          fallback: "Not ready to be processed: #{not_ready.length}",
          title: ":status_warning: Issues not ready to be processed: #{not_ready.length}",
          fields: issues_not_ready_to_be_processed
        }
      end

      def ready
        return {} if ready.empty?

        {
          fallback: "Ready to be processed: #{ready.length}",
          title: ":ballot_box_with_chec: Issues to be processed: #{ready.length}",
          fields: issues_ready_to_be_processed
        }
      end

      private

      def issues_not_ready_to_be_processed
        not_ready.each do |issue|
          {
            title: "Security implementation issue: ##{security_issue.iid}",
            value: "<#{security_issue.web_url}>",
            short: false
          }
        end
      end

      def issues_ready_to_be_processed
        ready.each do |issue|
          {
            title: "Security implementation issue: ##{security_issue.iid}",
            value: "<#{security_issue.web_url}>",
            short: false
          }
        end
      end
    end
  end
end
