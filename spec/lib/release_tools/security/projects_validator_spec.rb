# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Security::ProjectsValidator do
  let(:client) { double(:client) }
  let(:merge_requests_validator) { double(:merge_request_validator) }
  let(:projects_validator) { described_class.new(client) }

  describe '#execute' do
    let(:merge_request1) { double(:merge_request) }
    let(:merge_request2) { double(:merge_request) }
    let(:merge_request3) { double(:merge_request) }
    let(:merge_request4) { double(:merge_request) }

    it 'validates the merge requests per project' do
      allow(client)
        .to receive(:open_security_merge_requests)
        .with('gitlab-org/security/gitlab')
        .and_return([merge_request1, merge_request2])

      allow(client)
        .to receive(:open_security_merge_requests)
        .with('gitlab-org/security/omnibus-gitlab')
        .and_return([merge_request3, merge_request4])

      allow(ReleaseTools::Security::MergeRequestsValidator)
        .to receive(:new)
        .with(client)
        .and_return(merge_requests_validator)

      allow(merge_requests_validator)
        .to receive(:execute)
        .and_return(nil)

      expect(projects_validator)
        .to receive(:validate_merge_requests)
        .with([merge_request1, merge_request2])

      expect(projects_validator)
        .to receive(:validate_merge_requests)
        .with([merge_request3, merge_request4])

      projects_validator.execute
    end
  end
end
