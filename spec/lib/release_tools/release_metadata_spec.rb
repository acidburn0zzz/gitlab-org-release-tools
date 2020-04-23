# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::ReleaseMetadata do
  describe '#add_release' do
    it 'adds a release to the metadata collection' do
      collection = described_class.new

      collection.add_release(name: 'test')

      expect(collection.releases.values.first.name).to eq('test')
    end
  end

  describe '#tracked?' do
    it 'returns true when a release is tracked' do
      collection = described_class.new

      collection.add_release(name: 'test')

      expect(collection.tracked?('test')).to eq(true)
    end

    it 'returns false when a release is not tracked' do
      expect(described_class.new.tracked?('test')).to eq(false)
    end
  end

  describe '#add_auto_deploy_components' do
    context 'when using ignored component names' do
      it 'does not record release data for the components' do
        collection = described_class.new

        collection.add_auto_deploy_components(
          'VERSION' => '123',
          'GITLAB_VERSION' => '456'
        )

        expect(collection.releases).to be_empty
      end
    end

    context 'when using an already tracked component' do
      it 'does not overwrite the existing data' do
        collection = described_class.new
        project = ReleaseTools::Project::Gitaly

        collection.add_release(name: project.project_name, version: 'a')
        collection.add_auto_deploy_components(
          ReleaseTools::Project::Gitaly.version_file => 'a' * 40
        )

        expect(collection.releases.values.first.version).to eq('a')
      end
    end

    context 'when using a SHA as the component version' do
      it 'adds the release using the SHA as the commit and version' do
        collection = described_class.new
        sha = 'a' * 40

        collection.add_auto_deploy_components(
          ReleaseTools::Project::Gitaly.version_file => sha
        )

        release = collection.releases.values.first

        expect(release.name).to eq('gitaly')
        expect(release.version).to eq(sha)
        expect(release.sha).to eq(sha)
        expect(release.ref).to eq('master')
        expect(release.tag).to eq(false)
      end
    end

    context 'when using a MAJOR.MINOR version as the component version' do
      it 'adds the release data based on the associated Git tag' do
        collection = described_class.new

        tag = double(:tag, commit: double(:commit, id: '123'))

        expect(ReleaseTools::GitlabClient)
          .to receive(:tag)
          .with(ReleaseTools::Project::Gitaly.security_path, tag: 'v1.2.3')
          .and_return(tag)

        collection.add_auto_deploy_components(
          ReleaseTools::Project::Gitaly.version_file => '1.2.3'
        )

        release = collection.releases.values.first

        expect(release.name).to eq('gitaly')
        expect(release.version).to eq('1.2.3')
        expect(release.sha).to eq('123')
        expect(release.ref).to eq('v1.2.3')
        expect(release.tag).to eq(true)
      end

      it 'adds the release data based if there is no project' do
        collection = described_class.new

        collection.add_auto_deploy_components(
          'KITTENS_VERSION' => '1.2.3'
        )

        release = collection.releases.values.first

        expect(release.name).to eq('kittens')
        expect(release.version).to eq('1.2.3')
        expect(release.sha).to be_nil
        expect(release.ref).to eq('master')
        expect(release.tag).to eq(false)
      end

      it 'raises an ArgumentError if the associated Git tag does not exist' do
        collection = described_class.new

        expect(ReleaseTools::GitlabClient)
          .to receive(:tag)
          .with(ReleaseTools::Project::Gitaly.security_path, tag: 'v1.2.3')
          .and_raise(gitlab_error(:NotFound))

        expect do
          collection.add_auto_deploy_components(
            ReleaseTools::Project::Gitaly.version_file => '1.2.3'
          )
        end.to raise_error(ArgumentError)
      end
    end

    context 'when using a vMAJOR.MINOR version as the component version' do
      it 'adds the release data based on the associated Git tag' do
        collection = described_class.new

        tag = double(:tag, commit: double(:commit, id: '123'))

        expect(ReleaseTools::GitlabClient)
          .to receive(:tag)
          .with(ReleaseTools::Project::Gitaly.security_path, tag: 'v1.2.3')
          .and_return(tag)

        collection.add_auto_deploy_components(
          ReleaseTools::Project::Gitaly.version_file => 'v1.2.3'
        )

        release = collection.releases.values.first

        expect(release.name).to eq('gitaly')
        expect(release.version).to eq('1.2.3')
        expect(release.sha).to eq('123')
        expect(release.ref).to eq('v1.2.3')
        expect(release.tag).to eq(true)
      end
    end

    context 'when using an unrecognised component version' do
      it 'records the version using a generated name' do
        collection = described_class.new
        sha = 'a' * 40

        collection.add_auto_deploy_components('FOO_VERSION' => sha)

        release = collection.releases.values.first

        expect(release.name).to eq('foo')
        expect(release.version).to eq(sha)
        expect(release.sha).to eq(sha)
        expect(release.ref).to eq('master')
        expect(release.tag).to eq(false)
      end
    end

    context 'when using a version in an unsupported format' do
      it 'raises an ArgumentError' do
        collection = described_class.new

        expect do
          collection.add_auto_deploy_components(
            ReleaseTools::Project::Gitaly.version_file => 'hello'
          )
        end.to raise_error(ArgumentError)

        expect do
          collection.add_auto_deploy_components(
            ReleaseTools::Project::Gitaly.version_file => 'a' * 41
          )
        end.to raise_error(ArgumentError)
      end
    end
  end
end
