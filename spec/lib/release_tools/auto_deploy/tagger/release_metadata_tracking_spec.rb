# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::AutoDeploy::Tagger::ReleaseMetadataTracking do
  let(:tagger) do
    Class.new do
      include ReleaseTools::AutoDeploy::Tagger::ReleaseMetadataTracking

      attr_reader :release_metadata

      def initialize
        @release_metadata = ReleaseTools::ReleaseMetadata.new
      end

      def tag_name
        '1.2.3'
      end

      def version_map
        { ReleaseTools::Project::Gitaly.version_file => 'v1.2.3' }
      end

      def packager_name
        'cng-ee'
      end

      def target_branch
        'foo'
      end

      def gitlab_ref
        '467abc'
      end

      def packager_ref
        '978aff'
      end
    end.new
  end

  describe '#add_release_data' do
    it 'adds the release meta data' do
      enable_feature(:release_json_tracking)

      expect(tagger.release_metadata)
        .to receive(:add_release)
        .with(
          name: tagger.packager_name,
          version: tagger.packager_ref,
          sha: tagger.packager_ref,
          ref: tagger.target_branch
        )

      expect(tagger.release_metadata)
        .to receive(:add_release)
        .with(
          name: 'gitlab-ee',
          version: tagger.gitlab_ref,
          sha: tagger.gitlab_ref,
          ref: tagger.target_branch
        )

      expect(tagger.release_metadata)
        .to receive(:add_auto_deploy_components)
        .with(tagger.version_map)

      tagger.add_release_data
    end

    it 'does nothing when the feature flag is disabled' do
      expect(ReleaseTools::ReleaseMetadataUploader).not_to receive(:new)

      tagger.add_release_data
    end
  end
end
