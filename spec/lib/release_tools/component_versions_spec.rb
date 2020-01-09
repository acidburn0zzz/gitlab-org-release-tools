# frozen_string_literal: true

require 'spec_helper'

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

      expect(fake_client).to receive(:version_string_from_gemfile)
        .and_return("9.8.7\n")

      expect(described_class.get(project, commit_id)).to match(
        a_hash_including(
          'VERSION' => commit_id,
          file => '1.2.3',
          'mail_room' => '9.8.7'
        )
      )
    end
  end

  describe '.update_cng', skip: 'loop :-(' do
    let(:project) { ReleaseTools::Project::CNGImage }
    let(:version_map) do
      {
        'GITALY_SERVER_VERSION' => '1.33.0',
        'GITLAB_ELASTICSEARCH_INDEXER_VERSION' => '1.3.0',
        'GITLAB_PAGES_VERSION' => '1.5.0',
        'GITLAB_SHELL_VERSION' => '9.0.0',
        'GITLAB_WORKHORSE_VERSION' => '8.6.0',
        'VERSION' => '0cfa69752d82b8e134bdb8e473c185bdae26ccc2',
        'mail_room' => '0.10.0'
      }
    end
    let(:commit) { double('commit', id: 'abcd') }

    it 'commits version updates for the specified ref' do
      allow(fake_client).to receive(:project_path).and_return(project.path)

      without_dry_run do
        described_class.update_cng('foo-branch', version_map)
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

      expect(fake_client).to have_received(:create_commit).with(
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
        'mail_room' => '0.10.0'
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

  describe '.cng_version_changes?', skip: "loop :-(" do
    let(:project) { ReleaseTools::Project::CNGImage }
    let(:version_map) { { 'GITALY_SERVER_VERSION' => '1.33.0' } }

    it 'keeps cng versions that have changed' do
      allow(fake_client).to receive(:project_path).and_return(project.path)

      expect(fake_client).to receive(:file_contents)
        .with(project.path, "/GITALY_SERVER_VERSION", 'foo-branch')
        .and_return("1.2.3\n")

      expect(fake_client).to receive(:file_contents)
        .with(project.path, "/mail_room", 'foo-branch')

      expect(described_class.cng_version_changes?('foo-branch', version_map)).to be(true)
    end

    it 'rejects cng versions that have not changed' do
      allow(fake_client).to receive(:project_path).and_return(project.path)

      expect(fake_client).to receive(:file_contents)
        .with(project.path, "/GITALY_SERVER_VERSION", 'foo-branch')
        .and_return("1.33.0\n")

      expect(described_class.cng_version_changes?('foo-branch', version_map)).to be(false)
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
end
