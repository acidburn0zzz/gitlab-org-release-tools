# frozen_string_literal: true

module ReleaseTools
  module Slack
    class TagNotification < Webhook
      def self.webhook_url
        # NOTE: We return an empty String here rather than bubbling up to the
        # parent implementation. If a release manager doesn't set this in their
        # environment, it's fine to just skip the notification silently.
        ENV.fetch('SLACK_TAG_URL', '')
      end

      def self.release(project, version)
        text = "_#{SharedStatus.user}_ tagged `#{version}` on `#{project}`"

        text += " as a security release" if SharedStatus.security_release?

        if ENV['CI_JOB_URL']
          attachment = {
            fallback: '',
            color: 'good',
            text: "<#{ENV['CI_JOB_URL']}|#{text}>",
            mrkdwn_in: %w[text]
          }

          fire_hook(attachments: [attachment])
        else
          fire_hook(text: text)
        end
      end
    end
  end
end
