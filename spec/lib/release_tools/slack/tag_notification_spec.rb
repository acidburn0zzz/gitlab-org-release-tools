# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Slack::TagNotification do
  include SlackWebhookHelpers

  let(:webhook_url) { 'https://slack.example.com/' }

  describe '.webhook_url' do
    it 'returns blank when not set' do
      ClimateControl.modify(SLACK_TAG_URL: nil) do
        expect(described_class.webhook_url).to eq('')
      end
    end

    it 'returns ENV value when set' do
      ClimateControl.modify(SLACK_TAG_URL: webhook_url) do
        expect(described_class.webhook_url).to eq(webhook_url)
      end
    end
  end

  describe '.release' do
    let(:project) { ReleaseTools::Project::Gitaly }
    let(:version) { ReleaseTools::Version.new('10.4.20') }
    let(:message) { "_Liz Lemon_ tagged `#{version}` on `gitlab-org/gitaly`" }

    before do
      allow(ReleaseTools::SharedStatus).to receive(:user).and_return('Liz Lemon')
    end

    around do |ex|
      ClimateControl.modify(SLACK_TAG_URL: webhook_url) do
        ex.run
      end
    end

    context 'with a CI job URL' do
      it 'posts an attachment' do
        expect_post(
          json: {
            attachments: [{
              fallback: '',
              color: 'good',
              text: "<foo|#{message}>",
              mrkdwn_in: ['text']
            }]
          }
        ).and_return(response(200))

        ClimateControl.modify(CI_JOB_URL: 'foo') do
          described_class.release(project, version)
        end
      end
    end

    context 'without a CI job URL' do
      around do |ex|
        # Prevent these tests from failing on CI
        ClimateControl.modify(CI_JOB_URL: nil) do
          ex.run
        end
      end

      it 'posts a message' do
        expect_post(json: { text: message })
          .and_return(response(200))

        described_class.release(project, version)
      end

      it 'posts a message indicating a security release' do
        security_message = "_Liz Lemon_ tagged `#{version}` on `gitlab/gitaly` as a security release"

        expect_post(json: { text: security_message })
          .and_return(response(200))

        ClimateControl.modify(SECURITY: 'true') do
          described_class.release(project, version)
        end
      end
    end
  end
end
