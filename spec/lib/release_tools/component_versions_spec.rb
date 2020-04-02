# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::ComponentVersions do
  let(:fake_client) { spy }
  let(:target_branch) { '12-9-auto-deploy-20200218' }

  before do
    stub_const('ReleaseTools::GitlabClient', fake_client)
  end
  #
  # Omnibus
  # ----------------------------------------------------------------------

  describe '.get_omnibus_compat_versions' do
    it 'returns a Hash of component versions' do
      commit_id = '4d17177c8cc3fcab1079482af15b640d99c3f068'
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

  describe '.omnibus_version_changes?' do
    let(:version_map) { { 'GITALY_SERVER_VERSION' => '1.33.0' } }

    it 'keeps omnibus versions that have changed' do
      expect(fake_client).to receive(:file_contents)
        .with(described_class::OmnibusGitlab, "GITALY_SERVER_VERSION", target_branch)
        .and_return("1.2.3\n")

      expect(described_class.omnibus_version_changes?(target_branch, version_map)).to be(true)
    end

    it 'rejects omnibus versions that have not changed' do
      expect(fake_client).to receive(:file_contents)
        .with(described_class::OmnibusGitlab, "GITALY_SERVER_VERSION", target_branch)
        .and_return("1.33.0\n")

      expect(described_class.omnibus_version_changes?(target_branch, version_map)).to be(false)
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

    it 'does nothing without version changes' do
      expect(described_class).to receive(:omnibus_version_changes?)
        .and_return(false)
      expect(described_class).not_to receive(:commit_omnibus)

      without_dry_run do
        described_class.update_omnibus(target_branch, version_map)
      end
    end

    it 'commits version updates for the specified ref' do
      expect(described_class).to receive(:omnibus_version_changes?)
        .and_return(true)

      expect(described_class).to receive(:commit_omnibus)
        .with(target_branch, version_map)

      without_dry_run do
        described_class.update_omnibus(target_branch, version_map)
      end
    end
  end

  describe '.commit_omnibus' do
    let(:version_map) do
      {
        'VERSION' => '0cfa69752d82b8e134bdb8e473c185bdae26ccc2'
      }
    end

    it 'commits version updates for the specified ref' do
      without_dry_run do
        described_class.commit_omnibus(target_branch, version_map)
      end

      expect(fake_client).to have_received(:create_commit).with(
        described_class::OmnibusGitlab,
        target_branch,
        anything,
        array_including(
          action: 'update',
          file_path: '/VERSION',
          content: "#{version_map['VERSION']}\n"
        )
      )
    end
  end

  # CNG
  # ----------------------------------------------------------------------

  describe '.get_cng_compat_versions' do
    let(:gemfile_fixture) do
      File.read(File.join(VersionFixture.new.fixture_path, 'Gemfile.lock'))
    end

    it 'returns a Hash of component versions' do
      commit_id = '4d17177c8cc3fcab1079482af15b640d99c3f068'
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
      commit_id = '4d17177c8cc3fcab1079482af15b640d99c3f068'
      versions = {
        'VERSION' => commit_id,
        'GITALY_SERVER_VERSION' => '1.2.3',
        'SOME_RC_COMPONENT' => '12.9.0-rc5'
      }

      described_class.sanitize_cng_versions(versions)

      expect(versions).to match(
        a_hash_including(
          'GITLAB_VERSION' => commit_id,
          'GITLAB_ASSETS_TAG' => commit_id,
          'GITALY_SERVER_VERSION' => 'v1.2.3',
          'SOME_RC_COMPONENT' => 'v12.9.0-rc5'
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
        .with(described_class::CNGImage, 'ci_files/variables.yml', target_branch)
        .and_return(cng_variables)
    end

    it 'keeps cng versions that have changed' do
      expect(described_class.cng_version_changes?(target_branch, changed_version_map)).to be(true)
    end

    it 'rejects cng versions that have not changed' do
      expect(described_class.cng_version_changes?(target_branch, unchanged_version_map)).to be(false)
    end
  end

  describe '.update_cng' do
    let(:version_map) do
      {
        'GITALY_SERVER_VERSION' => 'v1.80.0',
        'GITLAB_ASSETS_TAG' => 'v12.7.0'
      }
    end

    it 'does nothing without version changes' do
      expect(described_class).to receive(:cng_version_changes?)
        .and_return(false)
      expect(described_class).not_to receive(:commit_cng)

      without_dry_run do
        described_class.update_cng(target_branch, version_map)
      end
    end

    it 'commits version updates for the specified ref' do
      expect(described_class).to receive(:cng_version_changes?)
        .and_return(true)

      expect(described_class).to receive(:commit_cng)
        .with(target_branch, version_map)

      without_dry_run do
        described_class.update_cng(target_branch, version_map)
      end
    end
  end

  describe '.commit_cng' do
    let(:version_map) do
      {
        'GITLAB_VERSION' => 'v12.7.0',
        'MAILROOM_VERSION' => '0.10.1'
      }
    end

    it 'commits new CNG variables' do
      # By stubbing this to an empty Hash, we verify that we merge the provided
      # argument
      expect(described_class).to receive(:cng_variables)
        .with(target_branch)
        .and_return({})

      without_dry_run do
        described_class.commit_cng(target_branch, version_map)
      end

      expect(fake_client).to have_received(:create_commit).with(
        described_class::CNGImage,
        target_branch,
        anything,
        array_including(
          action: 'update',
          file_path: 'ci_files/variables.yml',
          content: { 'variables' => version_map }.to_yaml
        )
      )
    end
  end
end
