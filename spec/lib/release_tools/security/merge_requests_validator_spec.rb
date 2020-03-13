# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Security::MergeRequestsValidator do
  let(:client) { double(:client) }
  let(:validator) { described_class.new(client) }

  describe '#execute' do
    it 'returns the valid merge requests' do
      merge_request1 = double(:merge_request, web_url: 'example.com')
      merge_request2 = double(:merge_request, web_url: 'example.com')

      allow(client)
        .to receive(:open_security_merge_requests)
        .with('gitlab-org/security/gitlab')
        .and_return([merge_request1])

      allow(client)
        .to receive(:open_security_merge_requests)
        .with('gitlab-org/security/omnibus-gitlab')
        .and_return([merge_request2])

      allow(validator)
        .to receive(:verify_merge_request)
        .with(merge_request1)
        .and_return([true, merge_request1])

      allow(validator)
        .to receive(:verify_merge_request)
        .with(merge_request2)
        .and_return([false, merge_request2])

      valid, invalid = validator.execute

      expect(valid).to eq([merge_request1])
      expect(invalid).to eq([merge_request2])
    end
  end

  describe '#verify_merge_request' do
    let(:basic_merge_request) do
      double(:basic_merge_request, project_id: 1, iid: 2, web_url: 'example.com')
    end

    let(:detailed_merge_request) { double(:detailed_merge_request, web_url: 'example.com') }

    context 'when the merge request is valid' do
      it 'returns the merge request' do
        merge_request_validator = double(:validator, validate: nil, errors: [])

        allow(client)
          .to receive(:merge_request)
          .with(1, 2)
          .and_return(detailed_merge_request)

        allow(ReleaseTools::Security::MergeRequestValidator)
          .to receive(:new)
          .with(detailed_merge_request, client)
          .and_return(merge_request_validator)

        allow(validator).to receive(:reassign_with_errors)

        expect(validator.verify_merge_request(basic_merge_request))
          .to eq([true, detailed_merge_request])

        expect(validator).not_to have_received(:reassign_with_errors)
      end
    end

    context 'when the merge request is invalid' do
      it 'reassigns the merge request' do
        merge_request_validator =
          double(:validator, validate: nil, errors: ['foo'])

        allow(client)
          .to receive(:merge_request)
          .with(1, 2)
          .and_return(detailed_merge_request)

        allow(ReleaseTools::Security::MergeRequestValidator)
          .to receive(:new)
          .with(detailed_merge_request, client)
          .and_return(merge_request_validator)

        allow(validator)
          .to receive(:reassign_with_errors)
          .with(detailed_merge_request, ['foo'])

        expect(validator.verify_merge_request(basic_merge_request))
          .to eq([false, detailed_merge_request])

        expect(validator).to have_received(:reassign_with_errors)
      end
    end
  end

  describe '#reassign_with_errors' do
    it 'reassigns the merge request and notifies the author using a note' do
      allow(client)
        .to receive(:create_merge_request_discussion)
        .with(1, 2, body: an_instance_of(String))

      allow(client)
        .to receive(:update_merge_request)
        .with(1, 2, assignee_id: 3)

      allow(client)
        .to receive(:release_tools_bot)
        .and_return(double(:bot, username: 'gitlab-release-tools-bot'))

      merge_request = double(
        :merge_request,
        author: double(:author, id: 3, username: 'alice'),
        project_id: 1,
        iid: 2,
        web_url: 'example.com'
      )

      without_dry_run do
        validator.reassign_with_errors(merge_request, ['foo'])
      end

      expect(client).to have_received(:create_merge_request_discussion)
      expect(client).to have_received(:update_merge_request)
    end
  end
end
