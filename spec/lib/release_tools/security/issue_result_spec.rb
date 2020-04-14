# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Security::IssueResult do
  let(:issue_result) { described_class.new }

  let(:issue1) do
    double(
      :issue,
      iid: 1,
      web_url: 'https://gitlab.com/gitlab-org/security/gitlab/issues/1'
    )
  end

  let(:issue2) do
    double(
      :issue,
      iid: 2,
      web_url: 'https://gitlab.com/gitlab-org/security/gitlab/issues/2'
    )
  end

  before do
    [issue1, issue2].each do |issue|
      issue_result.processed << issue
    end
  end

  describe '#slack_attachments' do
    context 'when all security issues were processed correctly' do
      it 'includes information about the issues' do
        total_output = issue_result.slack_attachments[0]

        expect(total_output[:fallback]).to eq('Total of security issues processed: 2.')
        expect(total_output[:title]).to eq(':information_source: Total: 2.')
        expect(total_output[:color]).to eq('good')

        invalid_output = issue_result.slack_attachments[1]
        expect(invalid_output).to be_empty

        pending_output = issue_result.slack_attachments[2]
        expect(pending_output).to be_empty
      end
    end

    context 'when security issues have invalid MRs' do
      it 'includes information about the issues' do
        issue_result.invalid << issue1

        total_output = issue_result.slack_attachments[0]

        expect(total_output[:fallback]).to eq('Total of security issues processed: 2.')
        expect(total_output[:title]).to eq(':information_source: Total: 2.')
        expect(total_output[:color]).to eq('good')

        invalid_output = issue_result.slack_attachments[1]

        invalid_fields = [
          {
            title: "Security implementation issue: ##{issue1.iid}",
            value: "<#{issue1.web_url}>",
            short: false
          }
        ]

        expect(invalid_output[:fallback]).to eq('Issues with invalid merge requests: 1.')
        expect(invalid_output[:title]).to eq(':warning: Issues with invalid merge requests: 1.')
        expect(invalid_output[:color]).to eq('warning')
        expect(invalid_output[:fields]).to eq(invalid_fields)

        pending_output = issue_result.slack_attachments[2]
        expect(pending_output).to be_empty
      end
    end

    context 'when security issues have pending MRs (not merged)' do
      it 'includes information about the issues' do
        mr1 = double(
          :merge_request,
          iid: 1,
          web_url: 'https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/1'
        )

        mr2 = double(
          :merge_request,
          iid: 2,
          web_url: 'https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/2'
        )

        issue3 = double(
          :issue,
          iid: 3,
          web_url: 'https://gitlab.com/gitlab-org/security/gitlab/issues/3',
          merge_requests: [mr1, mr2]
        )

        issue_result.processed << issue3
        issue_result.pending[issue3.iid] = issue3.merge_requests

        total_output = issue_result.slack_attachments[0]

        expect(total_output[:fallback]).to eq('Total of security issues processed: 3.')
        expect(total_output[:title]).to eq(':information_source: Total: 3.')
        expect(total_output[:color]).to eq('good')

        invalid_output = issue_result.slack_attachments[1]
        expect(invalid_output).to be_empty

        pending_output = issue_result.slack_attachments[2]
        pending_fields = [
          {
            title: 'Security implementation issue: #3',
            value: '<https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/1|!1>, <https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/2|!2>',
            short: false
          }
        ]

        expect(pending_output[:fallback]).to eq("Issues with merge requests that couldn't be merged: 1.")
        expect(pending_output[:title]).to eq(":warning: Issues with merge requests that couldn't be merged: 1.")
        expect(pending_output[:color]).to eq('warning')
        expect(pending_output[:fields]).to eq(pending_fields)
      end
    end
  end
end
