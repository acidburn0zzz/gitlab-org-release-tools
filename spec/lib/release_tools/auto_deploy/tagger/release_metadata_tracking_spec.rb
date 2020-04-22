# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::AutoDeploy::Tagger::ReleaseMetadataTracking do
  let(:tagger) do
    Class.new do
      include ReleaseTools::AutoDeploy::Tagger::ReleaseMetadataTracking

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

  describe '#upload_version_data' do
    it 'uploads the release meta data' do
      enable_feature(:release_json_tracking)

      data = ReleaseTools::ReleaseMetadata.new
      uploader = ReleaseTools::ReleaseMetadataUploader.new

      expect(ReleaseTools::ReleaseMetadataUploader)
        .to receive(:new)
        .and_return(uploader)

      expect(uploader)
        .to receive(:upload)
        .with('cng', '1.2.3', data)

      expect(data)
        .to receive(:add_auto_deploy_components)
        .with(tagger.version_map)

      tagger.upload_version_data('cng', data)
    end

    it 'does nothing when the feature flag is disabled' do
      expect(ReleaseTools::ReleaseMetadataUploader).not_to receive(:new)

      tagger.upload_version_data('cng')
    end
  end
end
