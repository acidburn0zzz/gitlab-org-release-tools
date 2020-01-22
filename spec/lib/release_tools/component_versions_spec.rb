# frozen_string_literal: true

require 'spec_helper'
require 'pry'

describe ReleaseTools::ComponentVersions do
  let(:fake_client) { spy }

  before do
    stub_const('ReleaseTools::GitlabClient', fake_client)
  end

  describe '.get' do
    it 'returns a Hash of component versions' do
      project = ReleaseTools::Project::GitlabEe
      commit_id = 'abcdefg'
      file = described_class::FILES.sample

      allow(fake_client).to receive(:project_path).and_return(project.path)
      expect(fake_client).to receive(:file_contents)
        .with(project.path, file, commit_id)
        .and_return("1.2.3\n")

      gemfile_lock = File.read("#{VersionFixture.new.fixture_path}/Gemfile.lock")
      expect(fake_client).to receive(:file_contents)
        .with(project.path, 'Gemfile.lock', commit_id)
        .and_return(gemfile_lock)

      expect(described_class.get(project, commit_id)).to match(
        a_hash_including(
          'VERSION' => commit_id,
          file => '1.2.3',
          'MAILROOM_VERSION' => '0.9.1'
        )
      )
    end
  end

  describe '.update_cng' do
    let(:project) { ReleaseTools::Project::CNGImage }
    let(:version_map) do
      {
        'GITALY_SERVER_VERSION' => '1.33.0',
        'GITLAB_ELASTICSEARCH_INDEXER_VERSION' => '1.3.0',
        'GITLAB_PAGES_VERSION' => '1.5.0',
        'GITLAB_SHELL_VERSION' => '9.0.0',
        'GITLAB_WORKHORSE_VERSION' => '8.6.0',
        'VERSION' => '0cfa69752d82b8e134bdb8e473c185bdae26ccc2',
        'MAILROOM_VERSION' => '0.10.0'
      }
    end
    let(:cng_variables) do
      {
        'variables' => {
          'GITALY_SERVER_VERSION' => '1.33.0',
          'GITLAB_ELASTICSEARCH_INDEXER_VERSION' => '1.3.0',
          'GITLAB_PAGES_VERSION' => '1.5.0',
          'GITLAB_SHELL_VERSION' => '9.0.0',
          'GITLAB_WORKHORSE_VERSION' => '8.6.0',
          'GITLAB_VERSION' => 'v12.7.0',
          'GITLAB_REF_SLUG' => 'v12.7.0',
          'GITLAB_ASSETS_TAG' => 'v12.7.0',
          'MAILROOM_VERSION' => '0.10.0'
        }
      }
    end
    let(:commit) { double('commit', id: 'abcd') }

    it 'commits version updates for the specified ref' do
      allow(fake_client).to receive(:project_path).and_return(project.path)
      allow(described_class).to receive(:cng_variables).and_return(cng_variables)

      expected_commit_content = <<~EOS
        ---
        variables:
          GITALY_SERVER_VERSION: v1.33.0
          GITLAB_ELASTICSEARCH_INDEXER_VERSION: v1.3.0
          GITLAB_PAGES_VERSION: v1.5.0
          GITLAB_SHELL_VERSION: v9.0.0
          GITLAB_WORKHORSE_VERSION: v8.6.0
          GITLAB_VERSION: 0cfa69752d82b8e134bdb8e473c185bdae26ccc2
          GITLAB_REF_SLUG: 0cfa69752d82b8e134bdb8e473c185bdae26ccc2
          GITLAB_ASSETS_TAG: 0cfa69752d82b8e134bdb8e473c185bdae26ccc2
          MAILROOM_VERSION: 0.10.0
      EOS

      expect(fake_client).to receive(:create_commit) do |path, branch, msg, actions|
        expect(path).to eq(project.path)
        expect(branch).to eq('foo-branch')
        expect(msg).to eq('Update component versions')

        expect(actions.length).to eq(1)
        action = actions[0]

        expect(action).to match(action: 'update', file_path: '/ci_files/variables.yml', content: String)

        committed_variables = YAML.safe_load(action[:content])
        expect(committed_variables['variables']).to match(YAML.safe_load(expected_commit_content)['variables'])
      end

      without_dry_run do
        described_class.update_cng('foo-branch', version_map)
      end

      expect(described_class).to have_received(:cng_variables).with('foo-branch')
    end
  end

  describe '.update_omnibus' do
    let(:project) { ReleaseTools::Project::OmnibusGitlab }
    let(:version_map) do
      {
        'GITALY_SERVER_VERSION' => '1.33.0',
        'GITLAB_ELASTICSEARCH_INDEXER_VERSION' => '1.3.0',
        'GITLAB_PAGES_VERSION' => '1.5.0',
        'GITLAB_SHELL_VERSION' => '9.0.0',
        'GITLAB_WORKHORSE_VERSION' => '8.6.0',
        'VERSION' => '0cfa69752d82b8e134bdb8e473c185bdae26ccc2',
        'MAILROOM_VERSION' => '0.10.0'
      }
    end
    let(:commit) { double('commit', id: 'abcd') }

    it 'commits version updates for the specified ref' do
      allow(fake_client).to receive(:project_path).and_return(project.path)

      without_dry_run do
        described_class.update_omnibus('foo-branch', version_map)
      end

      expect(fake_client).to have_received(:create_commit).with(
        project.path,
        'foo-branch',
        anything,
        array_including(
          action: 'update',
          file_path: '/VERSION',
          content: "#{version_map['VERSION']}\n"
        )
      )

      expect(fake_client).not_to have_received(:create_commit).with(
        project.path,
        'foo-branch',
        anything,
        array_including(
          action: 'update',
          file_path: '/mail_room',
          content: "#{version_map['mail_room']}\n"
        )
      )
    end
  end

  describe '.cng_version_changes?' do
    let(:cng_project) { ReleaseTools::Project::CNGImage }
    let(:cng_variables) do
      <<~EOS
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
    end

    before do
      allow(fake_client).to receive(:project_path)
        .with(cng_project)
        .and_return(cng_project.path)

      allow(fake_client).to receive(:file_contents)
        .with(cng_project.path, "/ci_files/variables.yml", 'foo-branch')
        .and_return(cng_variables)
    end

    it 'returns false when nothing changes' do
      version_map = {
        'GITALY_SERVER_VERSION' => '1.77.1',
        'VERSION' => '12.6.3',
        'MAILROOM_VERSION' => '0.10.0'
      }

      expect(described_class.cng_version_changes?('foo-branch', version_map)).to be(false)
    end

    it 'return true when gitlab changes' do
      gitlab_version = '8e956a0cb9f07c7fb7f91dd7886eb470e4feae84'
      version_map = {
        'GITALY_SERVER_VERSION' => '1.77.1',
        'VERSION' => gitlab_version,
        'MAILROOM_VERSION' => '0.10.0'
      }

      expect(described_class.cng_version_changes?('foo-branch', version_map)).to be(true)
    end

    it 'returns true when a component changes' do
      version_map = {
        'GITALY_SERVER_VERSION' => '1.77.2',
        'VERSION' => '12.6.3',
        'MAILROOM_VERSION' => '0.10.0'
      }

      expect(described_class.cng_version_changes?('foo-branch', version_map)).to be(true)
    end

    it 'returns true when a gem changes' do
      version_map = {
        'GITALY_SERVER_VERSION' => '1.77.1',
        'VERSION' => '12.6.3',
        'MAILROOM_VERSION' => '0.10.1'
      }

      expect(described_class.cng_version_changes?('foo-branch', version_map)).to be(true)
    end
  end

  describe '.versions_to_cng_variables' do
    let(:version_map) do
      {
        'GITALY_SERVER_VERSION' => '1.77.1',
        'VERSION' => '12.6.3',
        'MAILROOM_VERSION' => '0.10.0'
      }
    end

    let(:output) do
      {
        'MAILROOM_VERSION' => '0.10.0',
        'GITLAB_VERSION' => 'v12.6.3',
        'GITLAB_REF_SLUG' => 'v12.6.3',
        'GITLAB_ASSETS_TAG' => 'v12.6.3',
        'GITALY_VERSION' => 'v1.77.1'
      }
    end

    subject { described_class.versions_to_cng_variables(version_map) }

    it 'returns the correct output' do
      expect(subject).to eq(output)
    end

    it 'removes the VERSION' do
      expect(subject.keys).not_to include('VERSION')
    end

    it 'includes gitlab keys' do
      expect(subject.keys).to match_array(%w[GITLAB_VERSION GITLAB_REF_SLUG GITLAB_ASSETS_TAG GITALY_VERSION MAILROOM_VERSION])
    end

    it 'sets gitlab keys based on VERSION' do
      expect(subject['GITLAB_VERSION']).to eq('v12.6.3')
      expect(subject['GITLAB_REF_SLUG']).to eq('v12.6.3')
      expect(subject['GITLAB_ASSETS_TAG']).to eq('v12.6.3')
    end

    it 'transforms GITALY_SERVER_VERSION to GITALY_VERSION' do
      expect(subject['GITALY_VERSION']).to be_present
    end
  end

  describe '.omnibus_version_changes?' do
    let(:project) { ReleaseTools::Project::OmnibusGitlab }
    let(:version_map) { { 'GITALY_SERVER_VERSION' => '1.33.0' } }

    it 'keeps omnibus versions that have changed' do
      allow(fake_client).to receive(:project_path).and_return(project.path)

      expect(fake_client).to receive(:file_contents)
        .with(project.path, "/GITALY_SERVER_VERSION", 'foo-branch')
        .and_return("1.2.3\n")

      expect(fake_client).not_to receive(:file_contents)
        .with(project.path, "/mail_room", 'foo-branch')

      expect(described_class.omnibus_version_changes?('foo-branch', version_map)).to be(true)
    end

    it 'rejects omnibus versions that have not changed' do
      allow(fake_client).to receive(:project_path).and_return(project.path)

      expect(fake_client).to receive(:file_contents)
        .with(project.path, "/GITALY_SERVER_VERSION", 'foo-branch')
        .and_return("1.33.0\n")

      expect(described_class.omnibus_version_changes?('foo-branch', version_map)).to be(false)
    end
  end

  describe '#version_string_from_gemfile' do
    context 'when the Gemfile.lock contains the version we are looking for' do
      let(:fixture) { VersionFixture.new }
      let(:gemfile_lock) { File.read("#{fixture.fixture_path}/Gemfile.lock") }

      it 'returns the version' do
        expect do
          described_class.version_string_from_gemfile(gemfile_lock, 'mail_room')
        end.not_to raise_error

        expect(
          described_class.version_string_from_gemfile(gemfile_lock, 'mail_room')
        ).to eq('0.9.1')
      end
    end

    context 'when the Gemfile.lock does not contain the version we are looking for' do
      let(:fixture) { VersionFixture.new }
      let(:gemfile_lock) { File.read("#{fixture.fixture_path}/Gemfile.lock") }

      it 'raises a VersionNotFoundError' do
        expect do
          described_class.version_string_from_gemfile(gemfile_lock, 'gem_that_does_not_exist')
        end.to raise_error(described_class::VersionNotFoundError)
      end
    end
  end
end
