# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Deployments::SentryTracker do
  describe '#execute' do
    it 'works' do
      commit_id = '9bf75ddb8d878abc7f3cfb28718c391413bf5716'
      version   = '9bf75ddb8d8'

      client = double('HTTP')
      stub_const('HTTP', client)

      expected_payload = {
        version: version,
        projects: %w[gitlabcom staginggitlabcom],
        refs: [
          {
            repository: 'GitLab.org / security / 🔒 gitlab',
            commit: commit_id
          }
        ]
      }

      expect(client).to receive(:auth).with("Bearer token").and_return(client)
      expect(client).to receive(:post).with(
        'https://sentry.gitlab.net/api/0/organizations/gitlab/releases/',
        json: expected_payload
      )

      ClimateControl.modify(SENTRY_AUTH_TOKEN: 'token') do
        described_class.new(commit_id).execute
      end
    end
  end
end
