# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Services::SyncRemotesService do
  let(:version) { ReleaseTools::Version.new('1.2.3') }

  describe '#execute' do
    context 'when `publish_git` is disabled' do
      before do
        disable_all_features
      end

      it 'does nothing' do
        disable_feature(:publish_git)

        service = described_class.new(version)

        expect(service.execute).to be_nil
      end
    end

    context 'when `publish_git` is enabled' do
      before do
        disable_all_features
        enable_feature(:publish_git)
      end

      it 'syncs tags' do
        service = described_class.new(version)

        allow(service).to receive(:sync_branches).and_return(true)

        expect(service).to receive(:sync_tags)
          .with(ReleaseTools::Project::GitlabEe, 'v1.2.3-ee')
        expect(service).to receive(:sync_tags)
          .with(ReleaseTools::Project::GitlabCe, 'v1.2.3')
        expect(service).to receive(:sync_tags)
          .with(ReleaseTools::Project::OmnibusGitlab, '1.2.3+ee.0', '1.2.3+ce.0')

        service.execute
      end

      it 'syncs branches' do
        service = described_class.new(version)

        allow(service).to receive(:sync_tags).and_return(true)

        expect(service).to receive(:sync_branches)
          .with(ReleaseTools::Project::GitlabEe, '1-2-stable-ee')
        expect(service).to receive(:sync_branches)
          .with(ReleaseTools::Project::GitlabCe, '1-2-stable')
        expect(service).to receive(:sync_branches)
          .with(ReleaseTools::Project::OmnibusGitlab, '1-2-stable-ee', '1-2-stable')

        service.execute
      end
    end
  end

  describe '#sync_tags' do
    let(:fake_repo) { instance_double(ReleaseTools::RemoteRepository) }

    before do
      enable_feature(:publish_git, :publish_git_push)
    end

    it 'fetches tags and pushes' do
      tag = 'v1.2.3'

      allow(ReleaseTools::RemoteRepository).to receive(:get).and_return(fake_repo)

      expect(fake_repo).to receive(:fetch).with("refs/tags/#{tag}", remote: :dev)
      expect(fake_repo).to receive(:push_to_all_remotes).with(tag)

      described_class.new(version).sync_tags(spy, tag)
    end
  end

  describe '#sync_branches' do
    let(:fake_repo) { instance_double(ReleaseTools::RemoteRepository).as_null_object }
    let(:project) { ReleaseTools::Project::GitlabEe }

    before do
      enable_feature(:publish_git, :publish_git_push)
    end

    context 'with a succesful merge' do
      it 'merges branch and pushes' do
        branch = '1-2-stable-ee'

        successful_merge = double(status: double(success?: true))

        expect(ReleaseTools::RemoteRepository).to receive(:get)
          .with(anything, a_hash_including(branch: branch))
          .and_return(fake_repo)

        expect(fake_repo).to receive(:merge)
          .with("dev/#{branch}", branch, no_ff: true)
          .and_return(successful_merge)
        expect(fake_repo).to receive(:push_to_all_remotes).with(branch)

        described_class.new(version).sync_branches(project, branch)
      end
    end

    context 'with a failed merge' do
      it 'logs a fatal message with the output' do
        branch = '1-2-stable-ee'

        failed_merge = double(status: double(success?: false), output: 'output')

        allow(ReleaseTools::RemoteRepository).to receive(:get).and_return(fake_repo)

        expect(fake_repo).to receive(:merge).and_return(failed_merge)
        expect(fake_repo).not_to receive(:push_to_all_remotes)

        service = described_class.new(version)
        expect(service.logger).to receive(:fatal)
          .with(anything, a_hash_including(output: 'output'))

        service.sync_branches(project, branch)
      end
    end
  end
end
