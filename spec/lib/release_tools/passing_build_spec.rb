# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::PassingBuild do
  let(:project) { ReleaseTools::Project::GitlabCe }
  let(:fake_commit) { double('Commit', id: SecureRandom.hex(20), created_at: Time.now.to_s) }
  let(:version_map) { { 'VERSION' => '1.2.3' } }

  subject(:service) { described_class.new(project, 'master') }

  describe '#execute' do
    let(:fake_commits) { spy }

    before do
      stub_const('ReleaseTools::Commits', fake_commits)
    end

    it 'raises an error without a dev commit' do
      expect(fake_commits).to receive(:latest_successful_on_build)
        .and_return(nil)

      expect { service.execute(nil) }
        .to raise_error(/Unable to find a passing/)
    end

    it 'fetches component versions' do
      expect(fake_commits).to receive(:latest_successful_on_build)
        .and_return(fake_commit)

      expect(ReleaseTools::ComponentVersions)
        .to receive(:get).with(project, fake_commit.id)
        .and_return(version_map)

      expect(service).not_to receive(:trigger_build)

      service.execute(double(trigger_build: false))
    end

    it 'triggers a build when specified' do
      expect(fake_commits).to receive(:latest_successful_on_build)
        .and_return(fake_commit)

      expect(ReleaseTools::ComponentVersions)
        .to receive(:get).with(project, fake_commit.id)
        .and_return(version_map)

      expect(service).to receive(:trigger_build)

      service.execute(double(trigger_build: true))
    end
  end

  describe '#trigger_build' do
    let(:fake_client) { spy }
    let(:fake_ops_client) { spy }
    let(:project) { ReleaseTools::Project::GitlabCe }
    let(:version_map) { { 'VERSION' => '1.2.3' } }

    before do
      # Normally this gets set by `execute`, but we're bypassing that in specs
      service.instance_variable_set(:@version_map, version_map)
    end

    context 'when using auto-deploy' do
      let(:tag_name) { 'tag-name' }

      subject(:service) { described_class.new(project, '11-10-auto-deploy-1234') }

      before do
        allow(ReleaseTools::AutoDeploy::Naming).to receive(:tag)
          .and_return(tag_name)

        stub_const('ReleaseTools::GitlabClient', fake_client)
        stub_const('ReleaseTools::GitlabOpsClient', fake_ops_client)
      end

      context 'with component changes' do
        let(:cng_project) { ReleaseTools::Project::CNGImage }
        foo = <<EOS
---
variables:
GITLAB_ELASTICSEARCH_INDEXER_VERSION: v1.5.0
GITLAB_VERSION: v12.6.3
GITLAB_REF_SLUG: v12.6.3
GITLAB_ASSETS_TAG: v12.6.3
GITLAB_EXPORTER_VERSION: 5.1.0
GITLAB_SHELL_VERSION: v10.3.0
GITLAB_WORKHORSE_VERSION: v8.18.0
GITLAB_CONTAINER_REGISTRY_VERSION: v2.7.6-gitlab
GITALY_VERSION: master
GIT_VERSION: 2.24.1
GO_VERSION: 1.12.13
KUBECTL_VERSION: 1.13.12
PG_VERSION: '10.9'
MAILROOM_VERSION: 0.10.0
ALPINE_VERSION: '3.10'
CFSSL_VERSION: '1.2'
DOCKER_DRIVER: overlay2
DOCKER_HOST: tcp://docker:2375
DOCKER_TLS_CERTDIR: ''
ASSETS_IMAGE_PREFIX: gitlab-assets
ASSETS_IMAGE_REGISTRY_PREFIX: registry.gitlab.com/gitlab-org
GITLAB_NAMESPACE: gitlab-org
CE_PROJECT: gitlab-foss
EE_PROJECT: gitlab
COMPILE_ASSETS: 'false'
S3CMD_VERSION: 2.0.1
PYTHON_VERSION: 3.7.3
GITALY_SERVER_VERSION: v1.77.1
EOS
        let(:cng_variables) { YAML.safe_load(foo) }

        before do
          allow(fake_client).to receive(:project_path)
            .with(cng_project)
            .and_return(cng_project.path)

          allow(fake_client).to receive(:file_contents)
            .with(cng_project.path, "ci_files/variables.yml", '11-10-auto-deploy-1234')
            .and_return(cng_variables)
          allow(ReleaseTools::ComponentVersions)
            .to receive(:omnibus_version_changes?).and_return(true)

          allow(ReleaseTools::ComponentVersions)
            .to receive(:cng_version_changes?).and_return(true)
        end

        it 'updates Omnibus versions and tags' do
          expect(ReleaseTools::ComponentVersions)
            .to receive(:update_omnibus).with('11-10-auto-deploy-1234', version_map)
            .and_return(fake_commit)

          expect(service).to receive(:tag_project).with(ReleaseTools::Project::OmnibusGitlab, fake_commit)

          without_dry_run do
            service.trigger_build
          end
        end

        it 'updates CNG versions and tags' do
          expect(ReleaseTools::ComponentVersions)
            .to receive(:update_cng).with('11-10-auto-deploy-1234', version_map)
            .and_return(fake_commit)

          expect(service).to receive(:tag_project).with(ReleaseTools::Project::CNGImage, fake_commit)

          without_dry_run do
            service.trigger_build
          end
        end
      end

      context 'with Omnibus changes' do
        before do
          allow(ReleaseTools::ComponentVersions)
            .to receive(:omnibus_version_changes?).and_return(false)

          allow(ReleaseTools::ComponentVersions)
            .to receive(:cng_version_changes?).and_return(false)

          allow(service).to receive(:omnibus_changes?).and_return(true)
          allow(service).to receive(:cng_changes?).and_return(false)
        end

        it 'tags' do
          project = ReleaseTools::Project::OmnibusGitlab
          stub_const('ReleaseTools::Commits', spy(latest: fake_commit))
          expect(ReleaseTools::Commits)
            .to receive(:new).with(project, ref: '11-10-auto-deploy-1234')

          expect(service).to receive(:tag_project).with(project, fake_commit)

          service.trigger_build
        end
      end

      context 'with no changes' do
        before do
          allow(ReleaseTools::ComponentVersions)
            .to receive(:omnibus_version_changes?).and_return(false)

          allow(ReleaseTools::ComponentVersions)
            .to receive(:cng_version_changes?).and_return(false)

          allow(service).to receive(:omnibus_changes?).and_return(false)
          allow(service).to receive(:cng_changes?).and_return(false)
        end

        it 'does nothing' do
          expect(service).not_to receive(:tag_project)

          service.trigger_build
        end
      end
    end

    context 'when not using auto-deploy' do
      subject(:service) { described_class.new(project, 'master') }

      it 'triggers a pipeline build' do
        ClimateControl.modify(CI_PIPELINE_ID: '1234', OMNIBUS_BUILD_TRIGGER_TOKEN: 'token') do
          expect(ReleaseTools::GitlabDevClient)
            .to receive(:create_branch).with("master-1234", 'master', project)
          expect(ReleaseTools::Pipeline)
            .to receive(:new).with(project, 'master', version_map)
            .and_return(double(trigger: true))
          expect(ReleaseTools::GitlabDevClient)
            .to receive(:delete_branch).with("master-1234", project)

          VCR.use_cassette('pipeline/trigger') do
            service.trigger_build
          end
        end
      end
    end
  end

  describe '#tag_project' do
    let(:fake_client) { spy }
    let(:fake_ops_client) { spy }
    let(:tag_name) { 'tag-name' }

    before do
      allow(ReleaseTools::AutoDeploy::Naming).to receive(:tag)
        .and_return(tag_name)

      service.instance_variable_set(:@version_map, version_map)

      stub_const('ReleaseTools::GitlabClient', fake_client)
      stub_const('ReleaseTools::GitlabOpsClient', fake_ops_client)
    end

    it 'tags Omnibus with an annotated tag' do
      expect(service).to receive(:tag_project)
        .with(project, fake_commit)
        .and_call_original

      service.tag_project(project, fake_commit)

      expect(fake_client)
        .to have_received(:create_tag)
        .with(
          fake_client.project_path(project),
          tag_name,
          fake_commit.id,
          "Auto-deploy tag-name\n\nVERSION: 1.2.3"
        )
    end

    it 'tags Deployer with an annotated tag' do
      expect(service).to receive(:tag_deployer)
        .with(tag_name, anything, "master")
        .and_call_original

      service.tag_project(project, fake_commit)

      expect(fake_ops_client)
        .to have_received(:create_tag)
        .with(
          ReleaseTools::Project::Deployer.path,
          tag_name,
          "master",
          "Auto-deploy tag-name\n\nVERSION: 1.2.3"
        )
    end
  end
end
