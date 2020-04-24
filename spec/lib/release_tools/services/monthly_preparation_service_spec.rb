# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Services::MonthlyPreparationService do
  let(:internal_client) { spy('ReleaseTools::GitlabClient') }
  let(:version) { ReleaseTools::Version.new('12.1.0') }
  let(:remote_repo) { double(cleanup: true) }
  let(:version_manager) { double(:next_version) }

  subject(:service) { described_class.new(version) }

  before do
    allow(service).to receive(:gitlab_client).and_return(internal_client)
    allow(ReleaseTools::RemoteRepository).to receive(:get).with(ReleaseTools::Project::HelmGitlab.remotes).and_return(remote_repo)
    allow(ReleaseTools::Helm::VersionManager).to receive(:new).with(remote_repo).and_return(version_manager)
    allow(version_manager).to receive(:next_version).with(version.to_s).and_return(ReleaseTools::HelmChartVersion.new("4.3.0"))
  end

  describe '#create_label' do
    it 'does nothing on a dry run' do
      expect(ReleaseTools::PickIntoLabel).not_to receive(:create)

      service.create_label
    end

    it 'is idempotent' do
      allow(ReleaseTools::PickIntoLabel).to receive(:create)

      allow(internal_client).to receive(:create_branch)
        .and_raise(gitlab_error(:BadRequest, message: 'Label already exists'))

      without_dry_run do
        expect { service.create_label }.not_to raise_error
      end
    end

    it 'creates the label' do
      label_spy = spy
      stub_const('ReleaseTools::PickIntoLabel', label_spy)

      without_dry_run do
        service.create_label
      end

      expect(label_spy).to have_received(:create).with(version)
    end
  end

  describe '#create_stable_branches' do
    it 'does nothing on a dry run' do
      expect(internal_client).not_to receive(:create_branch)

      service.create_stable_branches
    end

    it 'is idempotent' do
      allow(internal_client).to receive(:create_branch)
        .and_raise(gitlab_error(:Conflict, message: 'Branch already exists'))

      without_dry_run do
        expect { service.create_stable_branches }.not_to raise_error
      end
    end

    it 'creates the EE stable branch' do
      without_dry_run do
        service.create_stable_branches
      end

      expect(internal_client).to have_received(:create_branch)
        .with('12-1-stable-ee', 'master', ReleaseTools::Project::GitlabEe)
    end

    it 'creates the CE stable branch' do
      without_dry_run do
        service.create_stable_branches
      end

      expect(internal_client).to have_received(:create_branch)
        .with('12-1-stable', '12-0-stable', ReleaseTools::Project::GitlabCe)
    end

    it 'creates the Omnibus stable branches' do
      without_dry_run do
        service.create_stable_branches
      end

      expect(internal_client).to have_received(:create_branch)
        .with('12-1-stable', 'master', ReleaseTools::Project::OmnibusGitlab)
    end

    it 'creates the CNG stable branch' do
      without_dry_run do
        service.create_stable_branches
      end

      expect(internal_client).to have_received(:create_branch)
        .with('12-1-stable', 'master', ReleaseTools::Project::CNGImage)
    end

    it 'creates Helm charts stable branches' do
      without_dry_run do
        service.create_stable_branches
      end

      expect(internal_client).to have_received(:create_branch)
        .with('4-3-stable', 'master', ReleaseTools::Project::HelmGitlab)
    end

    context 'when source is nil' do
      let(:version) { ReleaseTools::Version.new('12.6.0') }

      before do
        last_deployment = double('deployment', sha: '123abc', ref: '12-6-auto-deploy-20191215', created_at: '2019-12-17')
        allow(internal_client).to receive(:last_deployment)
                                    .with(ReleaseTools::Project::GitlabEe, 1_178_942)
                                    .and_return(last_deployment)
      end

      it 'creates the EE stable branch from SHA' do
        without_dry_run do
          service.create_stable_branches(nil)
        end

        expect(internal_client).to have_received(:create_branch)
                                     .with('12-6-stable-ee', '123abc', ReleaseTools::Project::GitlabEe)
      end

      it 'creates the Omnibus stable branches from branch name' do
        without_dry_run do
          service.create_stable_branches(nil)
        end

        expect(internal_client).to have_received(:create_branch)
                                     .with('12-6-stable', '12-6-auto-deploy-20191215', ReleaseTools::Project::OmnibusGitlab)
      end
    end
  end
end
