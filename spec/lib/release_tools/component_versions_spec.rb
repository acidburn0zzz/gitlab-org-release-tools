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
        'MAILROOM_VERSION' => '0.10.0'
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
