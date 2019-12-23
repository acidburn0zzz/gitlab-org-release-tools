# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Release::GitlabCeRelease do
  include RuggedMatchers

  # NOTE (rspeicher): There is some "magic" here that can be confusing.
  #
  # The release process checks out a remote to `/tmp/some_folder`, where
  # `some_folder` is based on the last part of a remote path, excluding `.git`.
  #
  # So `https://gitlab.com/foo/bar/repository.git` gets checked out to
  # `/tmp/repository`, and `/this/project/spec/fixtures/repositories/release`
  # gets checked out to `/tmp/release`.
  let(:repo_path)    { File.join(Dir.tmpdir, ReleaseFixture.repository_name) }
  let(:ob_repo_path) { File.join(Dir.tmpdir, OmnibusReleaseFixture.repository_name) }

  # These two Rugged repositories are used for _verifying the result_ of the
  # release run. Not to be confused with the fixture repositories.
  let(:repository)    { Rugged::Repository.new(repo_path) }
  let(:ob_repository) { Rugged::Repository.new(ob_repo_path) }

  # When enabled, operate as a security release
  let(:security_release) { false }

  before do
    cleanup!

    fixture    = ReleaseFixture.new
    ob_fixture = OmnibusReleaseFixture.new

    enable_feature(:security_remote)
    allow(ReleaseTools::SharedStatus).to receive(:security_release?)
      .and_return(security_release)

    fixture.rebuild_fixture!
    ob_fixture.rebuild_fixture!

    # Disable cleanup so that we can see what's the state of the temp Git repos
    allow_any_instance_of(ReleaseTools::RemoteRepository)
      .to receive(:cleanup)
      .and_return(true)

    # Override the actual remotes with our local fixture repositories
    allow_any_instance_of(described_class).to receive(:remotes)
      .and_return({ canonical: "file://#{fixture.fixture_path}" })

    allow_any_instance_of(ReleaseTools::Release::OmnibusGitlabRelease).to receive(:remotes)
      .and_return({ canonical: "file://#{ob_fixture.fixture_path}" })
  end

  after do
    cleanup!
  end

  def cleanup!
    # Manually perform the cleanup we disabled in the `before` block
    FileUtils.rm_rf(repo_path,    secure: true) if File.exist?(repo_path)
    FileUtils.rm_rf(ob_repo_path, secure: true) if File.exist?(ob_repo_path)
  end

  def execute(version, branch)
    cng_spy = spy
    stub_const('ReleaseTools::Release::CNGImageRelease', cng_spy)

    described_class.new(version).execute

    expect(cng_spy).to have_received(:execute)

    repository.checkout(branch)
    ob_repository.checkout(branch)
  end

  describe '#execute' do
    let(:changelog_manager) { double(release: true) }
    let(:ob_changelog_manager) { double(release: true) }

    before do
      allow(ReleaseTools::Changelog::Manager).to receive(:new).with(repo_path).and_return(changelog_manager)
      allow(ReleaseTools::Changelog::Manager).to receive(:new).with(ob_repo_path, 'CHANGELOG.md').and_return(ob_changelog_manager)
    end

    { ce: '', ee: '-ee' }.each do |edition, suffix|
      context 'with a security release' do
        let(:security_release) { true }
        let(:version) { "9.1.24#{suffix}" }
        let(:ob_version) { "9.1.24+#{edition}.0" }

        it "does not prefix all branches" do
          branch = "9-1-stable#{suffix}"

          execute(version, branch)

          aggregate_failures do
            expect(repository.branches.collect(&:name))
              .to include('master', branch)
            expect(repository.head.name).to eq "refs/heads/#{branch}"
            expect(repository.branches['master']).not_to be_nil
            expect(repository.branches['security/master']).to be_nil
            expect(repository.tags["v#{version}"]).not_to be_nil

            expect(ob_repository.branches.collect(&:name))
              .to include('master', branch)
            expect(ob_repository.head.name).to eq "refs/heads/#{branch}"
            expect(ob_repository.branches['master']).not_to be_nil
            expect(ob_repository.branches['security/master']).to be_nil
            expect(ob_repository.tags[ob_version]).not_to be_nil
          end
        end

        it 'includes [ci skip] when bumping version' do
          commit_message = "Update VERSION to 9.1.24#{suffix}\n\n[ci skip]"

          expect_any_instance_of(ReleaseTools::RemoteRepository)
            .to receive(:commit)
            .with('VERSION', message: commit_message)

          allow_any_instance_of(ReleaseTools::Release::OmnibusGitlabRelease)
            .to receive(:execute)
            .and_return(nil)

          allow_any_instance_of(ReleaseTools::Release::CNGImageRelease)
            .to receive(:execute)
            .and_return(nil)

          described_class.new(version).execute
        end
      end

      context "with an existing 9-1-stable#{suffix} stable branch, releasing a patch" do
        let(:version) { "9.1.24#{suffix}" }
        let(:ob_version) { "9.1.24+#{edition}.0" }
        let(:branch) { "9-1-stable#{suffix}" }

        describe "release GitLab#{suffix.upcase}" do
          it 'performs changelog compilation' do
            expect(changelog_manager).to receive(:release).with(version)
            execute(version, branch)
          end

          it 'creates a new branch and updates the version in VERSION, and creates a new branch, a new tag and updates the version files in the omnibus-gitlab repo' do
            execute(version, branch)

            aggregate_failures do
              # GitLab expectations
              expect(repository.head.name).to eq "refs/heads/#{branch}"
              expect(repository).to have_version.at(version)
              expect(repository.tags["v#{version}"]).not_to be_nil

              # Omnibus-GitLab expectations
              expect(ob_repository.head.name).to eq "refs/heads/#{branch}"
              expect(ob_repository.tags[ob_version]).not_to be_nil
              expect(ob_repository).to have_version.at(version)
              expect(ob_repository).to have_version('shell').at('2.2.2')
              expect(ob_repository).to have_version('workhorse').at('3.3.3')
              expect(ob_repository).to have_version('pages').at('4.4.4')
              expect(ob_repository).to have_version('gitaly').at('5.5.5')
            end
          end

          it 'does not fail if the tag already exists' do
            # Make sure we have the repository to create a conflicting tag
            described_class.new(version).__send__(:prepare_release)
            repository.tags.create("v#{version}", 'HEAD')

            expect(repository.tags["v#{version}"]).not_to be_nil
            expect { execute(version, branch) }.not_to raise_error
          end

          it 'does not fail when running twice' do
            expect { execute(version, branch) }.not_to raise_error
          end

          it 'includes [ci skip] when bumping version' do
            commit_message = "Update VERSION to 9.1.24#{suffix}\n\n[ci skip]"

            expect_any_instance_of(ReleaseTools::RemoteRepository)
              .to receive(:commit)
              .with('VERSION', message: commit_message)

            allow_any_instance_of(ReleaseTools::Release::OmnibusGitlabRelease)
              .to receive(:execute)
              .and_return(nil)

            allow_any_instance_of(ReleaseTools::Release::CNGImageRelease)
              .to receive(:execute)
              .and_return(nil)

            described_class.new(version).execute
          end
        end
      end

      context "with a new 10-1-stable#{suffix} stable branch, releasing an RC" do
        let(:version) { "10.1.0-rc13#{suffix}" }
        let(:ob_version) { "10.1.0+rc13.#{edition}.0" }
        let(:branch) { "10-1-stable#{suffix}" }

        describe "release GitLab#{suffix.upcase}" do
          it 'does not perform changelog compilation' do
            expect(ReleaseTools::Changelog::Manager).not_to receive(:new)

            execute(version, branch)
          end

          it 'creates a new branch and updates the version in VERSION, and creates a new branch, a new tag and updates the version files in the omnibus-gitlab repo' do
            execute(version, branch)

            aggregate_failures do
              # GitLab expectations
              expect(repository.head.name).to eq "refs/heads/#{branch}"
              expect(repository).to have_version.at(version)

              # Omnibus-GitLab expectations
              expect(ob_repository.head.name).to eq "refs/heads/#{branch}"
              expect(ob_repository.tags[ob_version]).not_to be_nil
              expect(ob_repository).to have_version.at(version)
              expect(ob_repository).to have_version('shell').at('2.3.0')
              expect(ob_repository).to have_version('workhorse').at('3.4.0')
              expect(ob_repository).to have_version('pages').at('4.5.0')
              expect(ob_repository).to have_version('gitaly').at('5.6.0')
            end
          end
        end
      end

      context "with a new 10-1-stable#{suffix} stable branch, releasing a stable .0" do
        let(:version) { "10.1.0#{suffix}" }
        let(:ob_version) { "10.1.0+#{edition}.0" }
        let(:branch) { "10-1-stable#{suffix}" }

        describe "release GitLab#{suffix.upcase}" do
          it 'performs changelog compilation' do
            expect(changelog_manager).to receive(:release).with(version)

            execute(version, branch)
          end

          it 'creates a new branch and updates the version in VERSION, and creates a new branch, a new tag and updates the version files in the omnibus-gitlab repo' do
            execute(version, branch)

            aggregate_failures do
              # GitLab expectations
              expect(repository.head.name).to eq "refs/heads/#{branch}"
              expect(repository).to have_version.at(version)

              repository.checkout('master')

              if edition == :ee
                expect(repository).to have_version.at('1.2.0')
                expect(repository.tags['v10.1.0-ee']).not_to be_nil
              else
                expect(repository).to have_version.at('10.2.0-pre')
                expect(repository.tags['v10.2.0.pre']).not_to be_nil
              end

              # Omnibus-GitLab expectations
              expect(ob_repository.head.name).to eq "refs/heads/#{branch}"
              expect(ob_repository.tags[ob_version]).not_to be_nil
              expect(ob_repository).to have_version.at(version)
              expect(ob_repository).to have_version('shell').at('2.3.0')
              expect(ob_repository).to have_version('workhorse').at('3.4.0')
              expect(ob_repository).to have_version('pages').at('4.5.0')
              expect(ob_repository).to have_version('gitaly').at('5.6.0')
            end
          end
        end
      end
    end
  end
end
