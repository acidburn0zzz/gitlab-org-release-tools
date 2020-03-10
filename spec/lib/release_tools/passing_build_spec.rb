# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::PassingBuild do
  let(:fake_commit) { double('Commit', id: SecureRandom.hex(20), created_at: Time.now.to_s) }
  let(:target_branch) { '11-10-auto-deploy-1234' }
  let(:omnibus_version_map) { { 'VERSION' => '1.2.3' } }
  let(:cng_version_map) do
    {
      'GITLAB_VERSION' => '1.2.3',
      'MAILROOM_VERSION' => '1.1.1'
    }
  end

  subject(:service) { described_class.new(target_branch) }

  describe '#execute' do
    let(:fake_commits) { spy }

    before do
      stub_const('ReleaseTools::Commits', fake_commits)
    end

    it 'raises an error without a dev commit' do
      expect(fake_commits).to receive(:latest_successful_on_build)
        .and_return(nil)

      expect { service.execute }
        .to raise_error(/Unable to find a passing/)
    end

    it 'fetches component versions' do
      expect(fake_commits).to receive(:latest_successful_on_build)
        .and_return(fake_commit)

      expect(ReleaseTools::ComponentVersions)
        .to receive(:get_omnibus_compat_versions).with(fake_commit.id)
        .and_return(omnibus_version_map)

      expect(ReleaseTools::ComponentVersions)
        .to receive(:get_cng_compat_versions).with(fake_commit.id)
        .and_return(cng_version_map)

      expect(service).not_to receive(:trigger_build)

      service.execute
    end

    it 'triggers a build when specified' do
      expect(fake_commits).to receive(:latest_successful_on_build)
        .and_return(fake_commit)

      expect(ReleaseTools::ComponentVersions)
        .to receive(:get_omnibus_compat_versions).with(fake_commit.id)
        .and_return(omnibus_version_map)

      expect(ReleaseTools::ComponentVersions)
        .to receive(:get_cng_compat_versions).with(fake_commit.id)
        .and_return(cng_version_map)

      expect(service).to receive(:trigger_build)

      service.execute(trigger: true)
    end
  end

  describe '#trigger_build' do
    context 'when using auto-deploy' do
      let(:tag_name) { 'tag-name' }

      it 'auto-deploys Omnibus and CNGImage' do
        expect(service).to receive(:auto_deploy_omnibus)
        expect(service).to receive(:auto_deploy_cng)

        service.trigger_build
      end
    end
  end

  describe '#tag_omnibus' do
    before do
      # Normally this gets set by `execute`, but we're bypassing that in specs
      service.instance_variable_set(:@omnibus_version_map, omnibus_version_map)
    end

    it 'updates Omnibus' do
      stub_const('ReleaseTools::AutoDeploy::Tagger::Omnibus', spy)

      expect(ReleaseTools::ComponentVersions).to receive(:update_omnibus)
        .with(target_branch, omnibus_version_map)

      service.auto_deploy_omnibus
    end

    it 'tags Omnibus' do
      stub_const('ReleaseTools::ComponentVersions', spy)
      tagger = stub_const('ReleaseTools::AutoDeploy::Tagger::Omnibus', spy)

      service.auto_deploy_omnibus

      expect(tagger).to have_received(:new).with(target_branch, omnibus_version_map)
      expect(tagger).to have_received(:tag!)
    end
  end

  describe '#tag_cng' do
    before do
      # Normally this gets set by `execute`, but we're bypassing that in specs
      service.instance_variable_set(:@cng_version_map, cng_version_map)
    end

    it 'updates CNG' do
      stub_const('ReleaseTools::AutoDeploy::Tagger::CNGImage', spy)

      expect(ReleaseTools::ComponentVersions).to receive(:update_cng)
        .with(target_branch, cng_version_map)

      service.auto_deploy_cng
    end

    it 'tags CNGImage' do
      stub_const('ReleaseTools::ComponentVersions', spy)
      tagger = stub_const('ReleaseTools::AutoDeploy::Tagger::CNGImage', spy)

      service.auto_deploy_cng

      expect(tagger).to have_received(:new).with(target_branch, cng_version_map)
      expect(tagger).to have_received(:tag!)
    end
  end
end
