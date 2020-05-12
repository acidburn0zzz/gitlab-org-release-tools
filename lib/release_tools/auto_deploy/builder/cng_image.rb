# frozen_string_literal: true

module ReleaseTools
  module AutoDeploy
    module Builder
      class CNGImage
        def initialize(target_branch, commit_id, release_metadata = ReleaseTools::ReleaseMetadata.new)
          @target_branch = target_branch
          @commit_id = commit_id
          @release_metadata = release_metadata
        end

        def execute
          version_map = ReleaseTools::ComponentVersions
            .get_cng_compat_versions(@commit_id)

          ReleaseTools::ComponentVersions
            .update_cng(@target_branch.to_s, version_map)

          ReleaseTools::AutoDeploy::Tagger::CNGImage
            .new(@target_branch, version_map, @release_metadata)
            .tag!
        end
      end
    end
  end
end
