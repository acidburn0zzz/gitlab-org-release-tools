# frozen_string_literal: true

module ReleaseTools
  module Security
    class BatchMergerResult
      attr_reader :processed, :pending, :invalid

      # Builds slack attachments based on Security::ImplementationIssues
      def initialize
        @processed = []
        @invalid = []
        @pending = Hash.new([])
      end

      def slack_attachments
        [
          total_issues,
          invalid_issues,
          pending_issues
        ]
      end

      private

      def total_issues
        {
          fallback: "Total of security issues processed: #{processed.length}.",
          title: ":information_source: Total: #{processed.length}.",
          color: 'good'
        }
      end

      def invalid_issues
        return {} if invalid.empty?

        {
          fallback: "Issues with invalid merge requests: #{invalid.length}.",
          title: ":warning: Issues with invalid merge requests: #{invalid.length}.",
          color: 'warning',
          fields: invalid_attachment_fields
        }
      end

      def pending_issues
        return {} if pending.empty?

        {
          fallback: "Issues with merge requests that couldn't be merged: #{pending.length}.",
          title: ":warning: Issues with merge requests that couldn't be merged: #{pending.length}.",
          color: 'warning',
          fields: pending_attachment_fields
        }
      end

      # Returns an array of issues with invalid merge requests.
      #
      # Example:
      #
      # [
      #   {
      #     title: "Security implementation issue: #2",
      #     value: "<https://gitlab.com/gitlab-org/security/gitlab/issues/2>",
      #     short: false
      #   }
      # ]
      def invalid_attachment_fields
        invalid.each.map do |security_issue|
          {
            title: "Security implementation issue: ##{security_issue.iid}",
            value: "<#{security_issue.web_url}>",
            short: false
          }
        end
      end

      # Returns an array of issues with pending (not merged) merge requests.
      #
      # Example:
      #
      # [
      #   {
      #     title: "Security implementation issue: #3",
      #     value: "<https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/1|!1>, <https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/2|!2>",
      #     short: false
      #   }
      # ]
      def pending_attachment_fields
        pending.each.map do |security_issue_iid, merge_requests|
          {
            title: "Security implementation issue: ##{security_issue_iid}",
            value: merge_requests.map { |mr| "<#{mr.web_url}|!#{mr.iid}>" }.join(', '),
            short: false
          }
        end
      end
    end
  end
end
