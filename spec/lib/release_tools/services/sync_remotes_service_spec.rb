# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Services::SyncRemotesService do
  let(:version) { ReleaseTools::Version.new('1.2.3') }

  describe '#execute' do
    it 'syncs tags' do
      service = described_class.new(version)

      allow(service).to receive(:sync_branches).and_return(true)

      expect(service).to receive(:sync_tags)
        .with(ReleaseTools::Project::GitlabEe, 'v1.2.3-ee')
      expect(service).to receive(:sync_tags)
        .with(ReleaseTools::Project::GitlabCe, 'v1.2.3')
      expect(service).to receive(:sync_tags)
        .with(ReleaseTools::Project::OmnibusGitlab, '1.2.3+ee.0', '1.2.3+ce.0')
      expect(service).to receive(:sync_tags)
        .with(ReleaseTools::Project::CNGImage, 'v1.2.3', 'v1.2.3-ee', 'v1.2.3-ubi8')

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
      expect(service).to receive(:sync_branches)
        .with(ReleaseTools::Project::CNGImage, '1-2-stable', '1-2-stable-ee')

      service.execute
    end
  end

  describe '#sync_branches' do
    let(:fake_repo) { instance_double(ReleaseTools::RemoteRepository).as_null_object }
    let(:project) { ReleaseTools::Project::GitlabEe }

    before do
      disable_feature(:security_remote)
    end

    context 'with invalid remotes' do
      it 'logs an error and returns' do
        service = described_class.new(version)

        allow(project).to receive(:remotes).and_return({})
        expect(service.logger).to receive(:fatal).once.and_call_original
        expect(ReleaseTools::RemoteRepository).not_to receive(:get)

        service.sync_branches(project, 'branch')
      end
    end

    context 'with a successful merge' do
      it 'merges branch and pushes' do
        branch = '1-2-stable-ee'

        successful_merge = double(status: double(success?: true))

        expect(ReleaseTools::RemoteRepository).to receive(:get)
          .with(
            a_hash_including(canonical: project.remotes.fetch(:canonical)),
            a_hash_including(branch: branch)
          ).and_return(fake_repo)

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

    context 'when security_remote is disabled' do
      it 'uses canonical and dev remotes' do
        branch = '1-2-stable-ee'
        remotes = project::REMOTES.slice(:canonical, :dev)
        successful_merge = double(status: double(success?: true))

        allow(fake_repo).to receive(:merge)
          .with("dev/#{branch}", branch, no_ff: true)
          .and_return(successful_merge)

        allow(fake_repo).to receive(:push_to_all_remotes).with(branch)

        expect(ReleaseTools::RemoteRepository).to receive(:get)
          .with(
            a_hash_including(remotes),
            a_hash_including(branch: branch)
          ).and_return(fake_repo)

        described_class.new(version).sync_branches(project, branch)
      end
    end

    context 'with security_remote is enabled' do
      it 'uses canonical, dev and security' do
        enable_feature(:security_remote)

        branch = '1-2-stable-ee'
        successful_merge = double(status: double(success?: true))

        allow(fake_repo).to receive(:merge)
          .with("dev/#{branch}", branch, no_ff: true)
          .and_return(successful_merge)

        allow(fake_repo).to receive(:push_to_all_remotes).with(branch)

        expect(ReleaseTools::RemoteRepository).to receive(:get)
          .with(
            a_hash_including(project::REMOTES),
            a_hash_including(branch: branch)
          ).and_return(fake_repo)

        described_class.new(version).sync_branches(project, branch)
      end
    end
  end

  describe '#sync_tags' do
    let(:fake_repo) { instance_double(ReleaseTools::RemoteRepository) }
    let(:tag) { 'v1.2.3' }

    before do
      disable_feature(:security_remote)
    end

    it 'fetches tags and pushes' do
      allow(ReleaseTools::RemoteRepository).to receive(:get).and_return(fake_repo)

      expect(fake_repo).to receive(:fetch).with("refs/tags/#{tag}", remote: :dev)
      expect(fake_repo).to receive(:push_to_all_remotes).with(tag)

      described_class.new(version).sync_tags(spy, tag)
    end

    context 'when security_remote is disabled' do
      it 'uses canonical and dev remotes' do
        project = ReleaseTools::Project::GitlabEe
        project_remotes = project::REMOTES.slice(:canonical, :dev)

        allow(fake_repo).to receive(:fetch).and_return(nil)
        allow(fake_repo).to receive(:push_to_all_remotes).and_return(nil)

        expect(ReleaseTools::RemoteRepository).to receive(:get)
          .with(
            a_hash_including(project_remotes),
            a_hash_including(global_depth: 1)
          ).and_return(fake_repo)

        described_class.new(version).sync_tags(project, tag)
      end
    end

    context 'when security_remote is enabled' do
      it 'uses canonical, dev and security remotes' do
        enable_feature(:security_remote)

        project = ReleaseTools::Project::GitlabEe

        allow(fake_repo).to receive(:fetch).and_return(nil)
        allow(fake_repo).to receive(:push_to_all_remotes).and_return(nil)

        expect(ReleaseTools::RemoteRepository).to receive(:get)
          .with(
            a_hash_including(project::REMOTES),
            a_hash_including(global_depth: 1)
          ).and_return(fake_repo)

        described_class.new(version).sync_tags(project, tag)
      end
    end
  end
end
