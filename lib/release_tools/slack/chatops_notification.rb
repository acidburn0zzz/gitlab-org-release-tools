# frozen_string_literal: true

module ReleaseTools
  module Slack
    class ChatopsNotification < Webhook
      def self.channel
        ENV.fetch('CHAT_CHANNEL', nil)
      end

      def self.job_url
        ENV.fetch('CI_JOB_URL', 'https://example.com/')
      end

      def self.task
        ENV.fetch('TASK', '')
      end

      def self.webhook_url
        ENV.fetch('SLACK_CHATOPS_URL')
      end

      def self.release_issue(issue)
        return unless task.present?

        text = "The `#{task}` command at #{job_url} completed!"
        attachment = {
          fallback: '',
          color: issue.status == :created ? 'good' : 'warning',
          title: issue.title,
          title_link: issue.url
        }

        fire_hook(text: text, attachments: [attachment], channel: channel)
      end

      # @param [ReleaseTools::Security::MergeResult] merge_result
      def self.merged_security_merge_requests(result)
        fire_hook(
          text: 'Finished merging security merge requests',
          channel: channel,
          attachments: result.slack_attachments
        )
      end

      # @param [ReleaseTools::Security::IssueResult] issue_result
      def self.security_issues_processed(result)
        fire_hook(
          text: 'Finished processing security implementation issues',
          channel: channel,
          attachments: result.slack_attachments
        )
      end

      def self.branch_status(status)
        return unless status.any?

        fields = []

        status.each_pair do |project, values|
          text = ["*#{project}*"]

          text << values.map do |result|
            ":status_#{result.status}: <#{result.web_url}|#{result.ref}>"
          end

          fields << mrkdwn(text.join("\n"))
        end

        blocks = [{ type: 'section', fields: fields }]

        fire_hook(channel: channel, blocks: blocks)
      end
    end
  end
end
