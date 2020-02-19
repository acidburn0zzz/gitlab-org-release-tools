# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::ComponentVersions do
  let(:fake_client) { spy }

  before do
    stub_const('ReleaseTools::GitlabClient', fake_client)
  end

  describe '.get_omnibus_compat_versions' do
    it 'returns a Hash of component versions' do
      commit_id = 'abcdefg'
      file = described_class::FILES.sample

      expect(fake_client).to receive(:file_contents)
        .with(described_class::SOURCE_PROJECT, file, commit_id)
        .and_return("1.2.3\n")

      expect(described_class.get_omnibus_compat_versions(commit_id)).to match(
        a_hash_including(
          'VERSION' => commit_id,
          file => '1.2.3'
        )
      )
    end
  end

  describe '.get_cng_compat_versions' do
    let(:gemfile_fixture) do
      File.read(File.join(VersionFixture.new.fixture_path, 'Gemfile.lock'))
    end

    it 'returns a Hash of component versions' do
      commit_id = 'abcdefg'
      file = described_class::FILES.sample

      expect(fake_client).to receive(:file_contents)
        .with(described_class::SOURCE_PROJECT, file, commit_id)
        .and_return("1.2.3\n")
      expect(fake_client).to receive(:file_contents)
        .with(described_class::SOURCE_PROJECT, 'Gemfile.lock', commit_id)
        .and_return(gemfile_fixture)

      versions = described_class.get_cng_compat_versions(commit_id)

      expect(versions).to match(
        a_hash_including(
          'GITLAB_VERSION' => commit_id,
          file => 'v1.2.3',
          'MAILROOM_VERSION' => '0.9.1'
        )
      )
    end
  end

  describe '.sanitize_cng_versions' do
    it 'returns a Hash of component versions' do
      commit_id = 'abcdefg'
      versions = {
        'VERSION' => commit_id,
        'GITALY_SERVER_VERSION' => '1.2.3'
      }

      described_class.sanitize_cng_versions(versions)

      expect(versions).to match(
        a_hash_including(
          'GITLAB_VERSION' => commit_id,
          'GITLAB_ASSETS_TAG' => commit_id,
          'GITALY_SERVER_VERSION' => 'v1.2.3'
        )
      )
    end
  end

  describe '.update_omnibus' do
    let(:version_map) do
      {
        'GITALY_SERVER_VERSION' => '1.33.0',
        'GITLAB_ELASTICSEARCH_INDEXER_VERSION' => '1.3.0',
        'GITLAB_PAGES_VERSION' => '1.5.0',
        'GITLAB_SHELL_VERSION' => '9.0.0',
        'GITLAB_WORKHORSE_VERSION' => '8.6.0',
        'VERSION' => '0cfa69752d82b8e134bdb8e473c185bdae26ccc2'
      }
    end
    let(:commit) { double('commit', id: 'abcd') }

    it 'commits version updates for the specified ref' do

      without_dry_run do
        described_class.update_omnibus('foo-branch', version_map)
      end

      expect(fake_client).to have_received(:create_commit).with(
        described_class::OmnibusGitlab,
        'foo-branch',
        anything,
        array_including(
          action: 'update',
          file_path: '/VERSION',
          content: "#{version_map['VERSION']}\n"
        )
      )
    end
  end

  describe '.cng_version_changes?' do
    let(:changed_version_map) do
      {
        'GITALY_SERVER_VERSION' => 'v1.80.0',
        'GITLAB_VERSION' => 'v12.7.0',
        'GITLAB_ASSETS_TAG' => 'v12.7.0',
        'MAILROOM_VERSION' => '0.10.1'
      }
    end
    let(:unchanged_version_map) do
      {
        'GITALY_SERVER_VERSION' => 'v1.77.1',
        'GITLAB_VERSION' => 'v12.6.3',
        'GITLAB_ASSETS_TAG' => 'v12.6.3',
        'MAILROOM_VERSION' => '0.10.0'
      }
    end
    let(:cng_variables) do
      <<~EOS
        variables:
          GITLAB_ELASTICSEARCH_INDEXER_VERSION: v1.5.0
          GITLAB_VERSION: v12.6.3
          GITLAB_REF_SLUG: v12.6.3
          GITLAB_ASSETS_TAG: v12.6.3
          GITLAB_EXPORTER_VERSION: 5.1.0
          GITLAB_SHELL_VERSION: v10.3.0
          GITLAB_WORKHORSE_VERSION: v8.18.0
          GITLAB_CONTAINER_REGISTRY_VERSION: v2.7.6-gitlab
          GITALY_SERVER_VERSION: v1.77.1
          MAILROOM_VERSION: 0.10.0
      EOS
    end

    before do
      allow(fake_client).to receive(:file_contents)
        .with(described_class::CNGImage, '/ci_files/variables.yml', 'foo-branch')
        .and_return(cng_variables)
    end

    it 'keeps cng versions that have changed' do
      expect(described_class.cng_version_changes?('foo-branch', changed_version_map)).to be(true)
    end

    it 'rejects cng versions that have not changed' do
      expect(described_class.cng_version_changes?('foo-branch', unchanged_version_map)).to be(false)
    end
  end

  describe '.omnibus_version_changes?' do
    let(:version_map) { { 'GITALY_SERVER_VERSION' => '1.33.0' } }

    it 'keeps omnibus versions that have changed' do
      expect(fake_client).to receive(:file_contents)
        .with(described_class::OmnibusGitlab, "/GITALY_SERVER_VERSION", 'foo-branch')
        .and_return("1.2.3\n")

      expect(described_class.omnibus_version_changes?('foo-branch', version_map)).to be(true)
    end

    it 'rejects omnibus versions that have not changed' do
      expect(fake_client).to receive(:file_contents)
        .with(described_class::OmnibusGitlab, "/GITALY_SERVER_VERSION", 'foo-branch')
        .and_return("1.33.0\n")

      expect(described_class.omnibus_version_changes?('foo-branch', version_map)).to be(false)
    end
  end
end
