# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Security::MergeRequestsValidator do
  let(:client) { double(:client) }
  let(:validator) { described_class.new(client) }

  describe '#execute' do
    it 'validates merge requests passed as arguments' do
      merge_request1 = double(:merge_request, web_url: 'example.com')
      merge_request2 = double(:merge_request, web_url: 'example.com')
      merge_request3 = double(:merge_request, web_url: 'example.com')
      merge_request4 = double(:merge_request, web_url: 'example.com')

      merge_requests = [merge_request1, merge_request2, merge_request3, merge_request4]

      allow(validator)
        .to receive(:validate_merge_request)
        .with(merge_request1)
        .and_return([true, merge_request1])

      allow(validator)
        .to receive(:validate_merge_request)
        .with(merge_request2)
        .and_return([false, merge_request2])

      allow(validator)
        .to receive(:validate_merge_request)
        .with(merge_request3)
        .and_return([true, merge_request3])

      allow(validator)
        .to receive(:validate_merge_request)
        .with(merge_request4)
        .and_return([false, merge_request4])

      expect(client).not_to receive(:open_security_merge_requests)

      valid, invalid = validator.execute(merge_requests: merge_requests)

      expect(valid).to match_array([merge_request1, merge_request3])
      expect(invalid).to match_array([merge_request2, merge_request4])
    end
  end

  describe '#validate_merge_request' do
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

        expect(validator.validate_merge_request(basic_merge_request))
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

        expect(validator.validate_merge_request(basic_merge_request))
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
