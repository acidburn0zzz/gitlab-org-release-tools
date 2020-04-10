# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Security::ImplementationIssue do
  let(:release_bot) do
    {
      id: described_class::GITLAB_RELEASE_BOT_ID,
      name: 'GitLab Release Bot'
    }
  end

  let(:mr1) do
    double(
      :merge_request,
      target_branch: 'master',
      assignees: [release_bot]
    )
  end

  let(:mr2) do
    double(
      :merge_request,
      target_branch: '12-10-stable-ee',
      assignees: [release_bot]
    )
  end

  let(:mr3) do
    double(
      :merge_request,
      target_branch: '12-9-stable-ee',
      assignees: [release_bot]
    )
  end

  let(:mr4) do
    double(
      :merge_request,
      target_branch: '12-8-stable-ee',
      assignees: [release_bot]
    )
  end

  let(:merge_requests) { [mr1, mr2, mr3, mr4] }

  subject { described_class.new(1, 1, merge_requests) }

  describe '#merge_requests_ready?' do
    context 'with 4 or more merge requests associated and all of them assigned to GitLab bot' do
      it { is_expected.to be_merge_requests_ready }
    end

    context 'with less than 4 associated merge requests' do
      let(:merge_requests) { [mr1, mr2] }

      it { is_expected.not_to be_merge_requests_ready }
    end

    context 'when a merge request is not assigned to the GitLab Release Bot' do
      let(:assignee1) do
        {
          id: 1234,
          name: 'Joe'
        }
      end

      let(:mr4) do
        double(
          :merge_request,
          target_branch: '12-10-stable-ee',
          assignees: [assignee1]
        )
      end

      it { is_expected.not_to be_merge_requests_ready }
    end
  end

  describe '#merge_request_master' do
    it 'returns the merge request targeting master' do
      expect(subject.merge_request_master).to eq(mr1)
    end
  end
end
