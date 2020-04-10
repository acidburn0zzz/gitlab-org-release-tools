# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Release::GitlabWorkhorseRelease do
  describe '#execute' do
    let(:changelog_manager) { double(release: true) }
    let(:gitlab_client) { spy('ReleaseTools::GitlabClient') }
    let(:dev_client) { spy('ReleaseTools::GitlabDevClient') }
    let(:client) { gitlab_client }
    let(:version) { ReleaseTools::Version.new('42.0.0') }
    let(:project) { ReleaseTools::Project::GitlabWorkhorse }

    # When enabled, operate as a security release
    let(:security_release) { false }

    subject(:release) { described_class.new(version) }

    before do
      stub_const('ReleaseTools::GitlabClient', gitlab_client)
      stub_const('ReleaseTools::GitlabDevClient', dev_client)

      enable_feature(:security_remote)
      allow(ReleaseTools::SharedStatus)
        .to receive(:security_release?)
        .and_return(security_release)

      allow(ReleaseTools::Changelog::ManagerApi)
        .to receive(:new).with(client, project, 'CHANGELOG', exclude_date: true)
        .and_return(changelog_manager)
    end

    shared_examples 'tags a release' do
      it 'updates the version in VERSION and creates a new tag' do
        without_dry_run do
          release.execute
        end

        aggregate_failures do
          expect(client).to have_received(:edit_file)
                              .with(
                                project,
                                'VERSION',
                                version.stable_branch,
                                "#{version}\n",
                                "Update VERSION to #{version}"
                              )
          expect(client).to have_received(:create_tag)
                              .with(
                                project,
                                version.tag,
                                version.stable_branch,
                                message: nil
                              )
        end
      end
    end

    context 'with an existing stable branch, releasing a patch' do
      let(:version) { ReleaseTools::Version.new('42.0.1') }

      before do
        allow(client).to receive(:find_branch)
                           .with(version.stable_branch, project)
                           .and_return(double('branch'))

        allow(client).to receive(:find_tag).and_return(nil)
      end

      it_behaves_like 'tags a release'

      it 'performs changelog compilation' do
        expect(changelog_manager).to receive(:release).with(version)
        without_dry_run do
          release.execute
        end
      end

      it 'does not create the stable branch' do
        without_dry_run do
          release.execute
        end

        expect(client).not_to have_received(:create_branch)
      end

      context 'when a tag already exists' do
        before do
          allow(client).to receive(:find_tag).and_return(double('tag'))
        end

        it 'does not fail' do
          expect do
            without_dry_run do
              release.execute
            end
          end.not_to raise_error

          expect(client).not_to have_received(:edit_file)
          expect(client).not_to have_received(:create_branch)
          expect(client).not_to have_received(:create_tag)
        end
      end
    end

    context 'when the stable branch does not exists' do
      before do
        allow(client).to receive(:find_branch)
                           .with(version.stable_branch, project)
                           .and_return(nil)

        allow(client).to receive(:find_tag).and_return(nil)
      end

      it_behaves_like 'tags a release'

      it 'does create the stable branch' do
        without_dry_run do
          release.execute
        end

        expect(client).to have_received(:create_branch)
                            .with(version.stable_branch, 'master', project)
      end

      it 'performs changelog compilation' do
        expect(changelog_manager).to receive(:release).with(version)

        without_dry_run do
          release.execute
        end
      end

      context 'releasing an RC' do
        let(:version) { ReleaseTools::Version.new('42.0.0-rc1') }

        it_behaves_like 'tags a release'

        it 'does not perform changelog compilation' do
          expect(ReleaseTools::Changelog::ManagerApi).not_to receive(:new)

          without_dry_run do
            release.execute
          end
        end
      end
    end

    context 'with a security release' do
      let(:security_release) { true }
      let(:client) { dev_client }

      before do
        allow(client).to receive(:find_branch)
                           .with(version.stable_branch, project)
                           .and_return(double('branch'))

        allow(client).to receive(:find_tag).and_return(nil)
      end

      describe 'release Workhorse' do
        it_behaves_like 'tags a release'

        it 'performs changelog compilation' do
          expect(changelog_manager).to receive(:release).with(version)
          without_dry_run do
            release.execute
          end
        end
      end
    end
  end
end
