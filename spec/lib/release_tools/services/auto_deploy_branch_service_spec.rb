# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Services::AutoDeployBranchService do
  let(:internal_client) { double('ReleaseTools::GitlabClient') }
  let(:internal_client_ops) { spy('ReleaseTools::GitlabOpsClient') }
  let(:branch_commit) { double(latest_successful: double(id: '1234')) }

  subject(:service) { described_class.new('branch-name') }

  before do
    stub_const('ReleaseTools::GitlabClient', internal_client)
    stub_const('ReleaseTools::GitlabOpsClient', internal_client_ops)
  end

  describe '#create_branches!' do
    it 'creates auto-deploy branches' do
      branch_name = 'branch-name'

      expect(service).to receive(:latest_successful_ref)
        .and_return(branch_commit)
        .exactly(4)
        .times
      expect(internal_client).to receive(:create_branch).with(
        branch_name,
        branch_commit,
        ReleaseTools::Project::GitlabEe
      )
      expect(internal_client).to receive(:create_branch).with(
        branch_name,
        branch_commit,
        ReleaseTools::Project::OmnibusGitlab
      )
      expect(internal_client).to receive(:create_branch).with(
        branch_name,
        branch_commit,
        ReleaseTools::Project::CNGImage
      )
      expect(internal_client).to receive(:create_branch).with(
        branch_name,
        branch_commit,
        ReleaseTools::Project::HelmGitlab
      )

      expect(internal_client_ops).to receive(:update_variable).with(
        'gitlab-org/release/tools',
        'AUTO_DEPLOY_BRANCH',
        branch_name
      )

      without_dry_run do
        service.create_branches!
      end
    end
  end
end
