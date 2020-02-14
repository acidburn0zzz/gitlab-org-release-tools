# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Release::GitalyRelease, :slow do
  include RuggedMatchers

  describe '.new' do
    let(:version) { '1.0.0' }
    let(:options) { { gitlab_repo_path: Dir.tmpdir } }

    subject { described_class.new(version, options) }

    it 'does not raise errors' do
      expect { subject }.not_to raise_error
    end

    context 'when the options hash has no gitlab_repo_path' do
      let(:options) { {} }

      it 'does raise an error' do
        expect { subject }.to raise_error ArgumentError, "missing gitlab_repo_path"
      end

      context 'when tag_from_master_head is true' do
        let(:options) { { tag_from_master_head: true } }

        it 'does raise an error' do
          expect { subject }
            .to raise_error(described_class.superclass::TaggingNotAllowed,
                            'only RC can be tagged from master')
        end

        context 'when releasing an RC' do
          let(:version) { '1.0.0-rc42' }

          it 'does not raise errors' do
            expect { subject }.not_to raise_error
          end
        end
      end
    end
  end

  describe '#execute' do
    # NOTE: There is some "magic" here that can be confusing.
    #
    # The release process checks out a remote to `/tmp/some_folder`, where
    # `some_folder` is based on the last part of a remote path, excluding `.git`.
    #
    # So `https://gitlab.com/foo/bar/repository.git` gets checked out to
    # `/tmp/repository`, and `/this/project/spec/fixtures/repositories/release`
    # gets checked out to `/tmp/release`.
    let(:repo_path) { File.join(Dir.tmpdir, GitalyReleaseFixture.repository_name) }

    # This Rugged repository is used for _verifying the result_ of the
    # release run. Not to be confused with the fixture repositories.
    let(:repository) { Rugged::Repository.new(repo_path) }

    # When enabled, operate as a security release
    let(:security_release) { false }

    let(:gitlab_repo_path) { Dir.mktmpdir('gitlab') }
    let(:gitaly_version_file_content) { fixture.repository.head.target_id }
    let(:changelog_manager) { double(release: true) }
    let(:fixture) { GitalyReleaseFixture.new }

    before do
      cleanup!

      enable_feature(:security_remote)
      allow(ReleaseTools::SharedStatus)
        .to receive(:security_release?)
        .and_return(security_release)

      fixture.rebuild_fixture!

      allow(ReleaseTools::Changelog::Manager)
        .to receive(:new).with(repo_path, 'CHANGELOG.md', include_date: false)
        .and_return(changelog_manager)

      Dir.mkdir(gitlab_repo_path)
      File.write(File.join(gitlab_repo_path, 'GITALY_SERVER_VERSION'), gitaly_version_file_content)
    end

    after do
      cleanup!
    end

    def cleanup!
      # Manually perform the cleanup we disabled in the `before` block
      FileUtils.rm_rf(repo_path, secure: true) if File.exist?(repo_path)
      FileUtils.rm_rf(gitlab_repo_path, secure: true) if File.exist?(gitlab_repo_path)
    end

    def execute(version, branch)
      release = described_class.new(version, gitlab_repo_path: gitlab_repo_path)

      # Override the actual remotes with our local fixture repositories
      allow(release).to receive(:remotes)
        .and_return(canonical: "file://#{fixture.fixture_path}")

      # Disable cleanup so that we can see what's the state of the temp Git repos
      allow(release.__send__(:repository)).to receive(:cleanup).and_return(true)

      yield release if block_given?

      release.execute

      repository.checkout(branch)
    end

    context 'with a security release' do
      let(:security_release) { true }
      let(:version) { '9.1.24' }

      it 'does not prefix all branches' do
        branch = "9-1-stable"

        execute(version, branch)

        aggregate_failures do
          expect(repository.branches.collect(&:name))
            .to include('master', branch)
          expect(repository.head.name).to eq "refs/heads/#{branch}"
          expect(repository.branches['master']).not_to be_nil
          expect(repository.branches['security/master']).to be_nil
          expect(repository.tags["v#{version}"]).not_to be_nil
        end
      end
    end

    context 'with an existing 9-1-stable stable branch, releasing a patch' do
      let(:version) { '9.1.24' }
      let(:branch) { '9-1-stable' }

      describe 'release Gitaly' do
        it 'performs changelog compilation' do
          expect(changelog_manager).to receive(:release).with(version, skip_master: false)
          execute(version, branch)
        end

        it 'updates the version in VERSION and creates a new tag' do
          execute(version, branch)

          aggregate_failures do
            expect(repository.head.name).to eq "refs/heads/#{branch}"
            expect(repository).to have_version.at(version)
            expect(repository.tags["v#{version}"]).not_to be_nil
          end
        end

        it 'does not fail if the tag already exists' do
          expect do
            execute(version, branch) do |release|
              # Make sure we have the repository to create a conflicting tag
              release.__send__(:prepare_release)
              repository.tags.create("v#{version}", 'HEAD')

              expect(repository.tags["v#{version}"]).not_to be_nil
            end
          end.not_to raise_error
        end
      end
    end

    context 'with a new 10-1-stable stable branch, releasing an RC' do
      let(:version) { '10.1.0-rc13' }
      let(:branch) { '10-1-stable' }

      describe 'release Gitaly' do
        it 'does not perform changelog compilation' do
          expect(ReleaseTools::Changelog::Manager).not_to receive(:new)

          execute(version, branch)
        end

        it 'updates the version in VERSION and creates a new tag' do
          execute(version, branch)

          aggregate_failures do
            expect(repository.head.name).to eq "refs/heads/#{branch}"
            expect(repository).to have_version.at(version)
            expect(repository.tags["v#{version}"]).not_to be_nil
          end
        end
      end
    end

    context 'with a new 10-1-stable stable branch, releasing a stable .0' do
      let(:version) { '10.1.0' }
      let(:branch) { '10-1-stable' }

      describe 'release Gitaly' do
        it 'performs changelog compilation only on stable branch' do
          expect(changelog_manager).to receive(:release).with(version, skip_master: true)

          execute(version, branch)
        end

        it 'updates the version in VERSION and creates a new tag' do
          execute(version, branch)

          aggregate_failures do
            expect(repository.head.name).to eq "refs/heads/#{branch}"
            expect(repository).to have_version.at(version)

            repository.checkout('master')
            expect(repository).to have_version.at(version)
          end
        end

        it 'merges stable branch into master' do
          execute(version, branch)

          aggregate_failures do
            repository.checkout('master')

            expect(repository).to have_version.at(version)
            expect(repository).to have_commit_title("Merge branch '#{branch}'")
          end
        end

        context 'when not releasing from master HEAD' do
          let(:gitaly_version_file_content) { fixture.repository.head.target.parent_oids.first }

          it 'merges stable branch into master' do
            execute(version, branch)

            aggregate_failures do
              expect(repository).not_to have_blob('on_master_head').for(branch)

              expect(repository).to have_blob('on_master_head').for('master')
              expect(repository).to have_commit_title("Merge branch '#{branch}'").for('master')
            end
          end
        end
      end
    end
  end
end
