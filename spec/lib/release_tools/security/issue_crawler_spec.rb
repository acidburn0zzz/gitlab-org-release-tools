# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Security::IssueCrawler do
  describe '#security_release_issues' do
    it 'returns all security release issues' do
      issue1 = double(:issue, due_date: '2020-01-04')
      issue2 = double(:issue, due_date: '2020-01-01')
      page = Gitlab::PaginatedResponse.new([issue1, issue2])

      allow(ReleaseTools::GitlabClient)
        .to receive(:issues)
        .with(
          described_class::PUBLIC_PROJECT,
          labels: described_class::ROOT_ISSUE_LABEL,
          state: 'opened'
        )
        .and_return(page)

      expect(described_class.new.security_release_issues)
        .to eq([issue2, issue1])
    end

    it 'raises an error when finding a security issue without a due date' do
      issue = double(:issue, due_date: nil, web_url: 'foo')
      page = Gitlab::PaginatedResponse.new([issue])

      allow(ReleaseTools::GitlabClient)
        .to receive(:issues)
        .with(
          described_class::PUBLIC_PROJECT,
          labels: described_class::ROOT_ISSUE_LABEL,
          state: 'opened'
        )
        .and_return(page)

      expect { described_class.new.security_release_issues }
        .to raise_error(RuntimeError)
    end
  end

  describe '#upcoming_security_issues_and_merge_requests' do
    context 'when there are no security release issues' do
      it 'returns an empty Array' do
        crawler = described_class.new

        allow(crawler).to receive(:security_release_issues).and_return([])

        expect(crawler.upcoming_security_issues_and_merge_requests).to eq([])
      end
    end

    context 'when there are security release issues' do
      it 'returns all security issues and merge requests for the most recent issue' do
        crawler = described_class.new
        issue1 = double(:issue, iid: 1)
        issue2 = double(:issue, iid: 2)

        allow(crawler)
          .to receive(:security_release_issues)
          .and_return([issue1, issue2])

        expect(crawler)
          .to receive(:security_issues_and_merge_requests_for)
          .with(issue1.iid)

        crawler.upcoming_security_issues_and_merge_requests
      end
    end
  end

  describe '#security_issues_and_merge_requests_for' do
    it 'returns the security issues and merge requests related to the release issue' do
      issue1 = double(
        :issue,
        project_id: 1,
        iid: 1,
        labels: [described_class::SECURITY_LABEL],
        web_url: 'https://gitlab.com/gitlab-org/security/gitlab/issues/1'
      )

      issue2 = double(
        :issue,
        project_id: 1,
        iid: 2,
        labels: [],
        web_url: 'https://gitlab.com/gitlab-org/security/gitlab/issues/2'
      )

      issue3 = double(
        :issue,
        project_id: 2,
        iid: 1,
        labels: [described_class::SECURITY_LABEL],
        web_url: 'https://gitlab.com/gitlab-org/gitlab/issues/1'
      )

      mr1 = double(
        :merge_request,
        labels: [described_class::SECURITY_LABEL],
        state: described_class::OPENED,
        web_url: 'https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/1'
      )

      mr2 = double(
        :merge_request,
        labels: [],
        state: described_class::OPENED,
        web_url: 'https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/1'
      )

      mr3 = double(
        :merge_request,
        labels: [described_class::SECURITY_LABEL],
        state: described_class::OPENED,
        web_url: 'https://gitlab.com/gitlab-org/gitlab/-/merge_requests/1'
      )

      issue_page = Gitlab::PaginatedResponse.new([issue1, issue2, issue3])
      mr_page = Gitlab::PaginatedResponse.new([mr1, mr2, mr3])

      allow(ReleaseTools::GitlabClient.client)
        .to receive(:issue_links)
        .with(described_class::PUBLIC_PROJECT, 1)
        .and_return(issue_page)

      allow(ReleaseTools::GitlabClient)
        .to receive(:related_merge_requests)
        .with(1, 1)
        .and_return(mr_page)

      issues = described_class.new.security_issues_and_merge_requests_for(1)

      expect(issues.length).to eq(1)
      expect(issues[0].project_id).to eq(1)
      expect(issues[0].iid).to eq(1)
      expect(issues[0].merge_requests).to eq([mr1])
    end

    it 'filters out closed merge requests' do
      issue1 = double(
        :issue,
        project_id: 1,
        iid: 1,
        labels: [described_class::SECURITY_LABEL],
        web_url: 'https://gitlab.com/gitlab-org/security/gitlab/issues/1'
      )

      mr1 = double(
        :merge_request,
        labels: [described_class::SECURITY_LABEL],
        state: described_class::OPENED,
        web_url: 'https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/1'
      )

      mr2 = double(
        :merge_request,
        labels: [described_class::SECURITY_LABEL],
        state: 'closed',
        web_url: 'https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/2'
      )

      mr3 = double(
        :merge_request,
        labels: [described_class::SECURITY_LABEL],
        state: described_class::OPENED,
        web_url: 'https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/3'
      )

      issue_page = Gitlab::PaginatedResponse.new([issue1])
      mr_page = Gitlab::PaginatedResponse.new([mr1, mr2, mr3])

      allow(ReleaseTools::GitlabClient.client)
        .to receive(:issue_links)
        .with(described_class::PUBLIC_PROJECT, 1)
        .and_return(issue_page)

      allow(ReleaseTools::GitlabClient)
        .to receive(:related_merge_requests)
        .with(1, 1)
        .and_return(mr_page)

      issues = described_class.new.security_issues_and_merge_requests_for(1)

      expect(issues[0].merge_requests.length).to eq(2)
      expect(issues[0].merge_requests).not_to include(mr2)
    end
  end
end
