# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Security::MergeRequestsMerger do
  let(:client) { double(:client) }

  describe '#execute' do
    it 'merges valid merge requests' do
      merger = described_class.new(client)
      mr1 = double(:merge_request, target_branch: 'foo', web_url: 'example.com')
      mr2 = double(:merge_request, target_branch: 'bar', web_url: 'example.com')
      mr3 = double(:merge_request, target_branch: 'invalid', web_url: 'example.com')
      merged_mr = double(:merge_request, merge_commit_sha: 'a')
      result = double(:result)

      allow(merger)
        .to receive(:validated_merge_requests)
        .and_return([[mr1, mr2], [mr3]])

      allow(merger)
        .to receive(:merge)
        .with(mr1)
        .and_return([true, merged_mr])

      allow(merger)
        .to receive(:merge)
        .with(mr2)
        .and_return([false, mr2])

      allow(ReleaseTools::Security::MergeResult)
        .to receive(:from_array)
        .with(valid: [[true, merged_mr], [false, mr2]], invalid: [mr3])
        .and_return(result)

      expect(ReleaseTools::Slack::ChatopsNotification)
        .to receive(:merged_security_merge_requests)
        .with(result)

      without_dry_run do
        merger.execute
      end
    end

    it 'performs cherry-picking when `merge_master` is true' do
      picker = spy(:CherryPicker)
      master_mr = double(:merge_request, target_branch: 'master', web_url: 'example.com')
      backport = double(:merge_request, target_branch: '11-8-stable', web_url: 'example.com')

      stub_const('ReleaseTools::Slack::ChatopsNotification', spy)
      stub_const('ReleaseTools::Security::CherryPicker', picker)

      described_class.new(client, merge_master: true).tap do |instance|
        allow(instance).to receive(:merge)
          .and_return([true, master_mr])
        allow(instance).to receive(:validated_merge_requests)
          .and_return([[master_mr], [backport]])

        without_dry_run do
          instance.execute
        end
      end

      expect(picker).to have_received(:new).with([master_mr])
      expect(picker).to have_received(:execute)
    end
  end

  describe '#validated_merge_requests' do
    let(:validator) { double(:validator) }

    before do
      allow(ReleaseTools::Security::MergeRequestsValidator)
        .to receive(:new)
        .and_return(validator)
    end

    context 'when merging to master is enabled' do
      it 'includes merge requests that target master' do
        master_mr = double(:merge_request, target_branch: 'master')
        backport = double(:merge_request, target_branch: '11-8-stable')
        merger = described_class.new(client, merge_master: true)

        allow(validator)
          .to receive(:execute)
          .and_return([master_mr, backport])

        expect(merger.validated_merge_requests).to eq([master_mr, backport])
      end
    end

    context 'when merging to master is not enabled' do
      it 'does not include merge requests that target master' do
        master_mr = double(:merge_request, target_branch: 'master')
        backport = double(:merge_request, target_branch: '11-8-stable')
        invalid = double(:merge_request, target_branch: 'invalid')
        merger = described_class.new(client, merge_master: false)

        allow(validator)
          .to receive(:execute)
          .and_return([[master_mr, backport], [invalid]])

        expect(merger.validated_merge_requests).to eq([[backport], [invalid]])
      end
    end
  end

  describe '#merge' do
    it 'returns true when the merge request is merged' do
      mr = double(:merge_request, project_id: 1, iid: 2, web_url: 'example.com')
      merger = described_class.new(client)
      response = double(:response, merge_commit_sha: '123')

      allow(client)
        .to receive(:accept_merge_request)
        .with(1, 2, squash: true)
        .and_return(response)

      without_dry_run do
        expect(merger.merge(mr)).to eq([true, response])
      end
    end

    it 'reassigns the MR when the merge commit SHA is empty' do
      mr = double(:merge_request, project_id: 1, iid: 2, web_url: 'example.com')
      merger = described_class.new(client)
      response = double(:response, merge_commit_sha: nil)

      allow(merger.client)
        .to receive(:accept_merge_request)
        .with(1, 2, squash: true)
        .and_return(response)

      allow(merger)
        .to receive(:reassign_merge_request)
        .with(mr)

      without_dry_run do
        expect(merger.merge(mr)).to eq([false, mr])
      end
    end

    it 'reassigns the MR when the merge commit SHA is missing' do
      mr = double(:merge_request, project_id: 1, iid: 2, web_url: 'example.com')
      merger = described_class.new(client)

      allow(merger.client)
        .to receive(:accept_merge_request)
        .with(1, 2, squash: true)
        .and_return(double(:response))

      allow(merger)
        .to receive(:reassign_merge_request)
        .with(mr)

      without_dry_run do
        expect(merger.merge(mr)).to eq([false, mr])
      end
    end
  end

  describe '#reassign_merge_request' do
    it 'reassigns the merge request and notifies the author' do
      merger = described_class.new(client)
      mr = double(
        :merge_request,
        project_id: 1,
        iid: 2,
        author: double(:author, id: 3, username: 'alice'),
        web_url: 'example.com'
      )

      allow(merger.client)
        .to receive(:create_merge_request_discussion)
        .with(1, 2, body: an_instance_of(String))

      allow(merger.client)
        .to receive(:update_merge_request)
        .with(1, 2, assignee_id: 3)

      merger.reassign_merge_request(mr)
    end
  end
end
