# frozen_string_literal: true

module ReleaseTools
  module AutoDeploy
    module Tagger
      module ReleaseMetadataTracking
        def add_release_data
          return unless Feature.enabled?(:release_json_tracking)

          # The packager (e.g. Omnibus) and GitLab EE are released from an
          # auto-deploy branch, so we record these manually (ensuring the right
          # branch is used) instead of relying on the component version mapping
          # Hash.
          release_metadata.add_release(
            name: packager_name,
            version: packager_ref,
            sha: packager_ref,
            ref: target_branch
          )

          release_metadata.add_release(
            name: 'gitlab-ee',
            version: gitlab_ref,
            sha: gitlab_ref,
            ref: target_branch
          )

          release_metadata.add_auto_deploy_components(version_map)
        end

        def release_metadata
          raise NotImplementedError
        end

        def tag_name
          raise NotImplementedError
        end

        def version_map
          raise NotImplementedError
        end

        def packager_name
          raise NotImplementedError
        end

        def target_branch
          raise NotImplementedError
        end

        def gitlab_ref
          raise NotImplementedError
        end

        def packager_ref
          raise NotImplementedError
        end
      end
    end
  end
end
