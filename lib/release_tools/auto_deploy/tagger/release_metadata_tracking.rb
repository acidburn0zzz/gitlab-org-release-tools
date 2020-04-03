# frozen_string_literal: true

module ReleaseTools
  module AutoDeploy
    module Tagger
      module ReleaseMetadataTracking
        # Uploads the release data of an auto-deploy.
        #
        # The `category` arguments describes the "category" of the release, such
        # as "cng" for CNG releases and "omnibus" for Omnibus releases.
        def upload_version_data(category, release_metadata = ReleaseMetadata.new)
          return unless Feature.enabled?(:release_json_tracking)

          # The packager (e.g. Omnibus) and GitLab EE are released from an
          # auto-deploy branch, so we record these manually (ensuring the right
          # branch is used) instead of relying on the component version mapping
          # Hash.
          release_metadata.add_release(
            name: packager_project.project_name,
            version: packager_ref,
            sha: packager_ref,
            ref: target_branch
          )

          release_metadata.add_release(
            name: Project::GitlabEe.project_name,
            version: gitlab_ref,
            sha: gitlab_ref,
            ref: target_branch
          )

          release_metadata.add_auto_deploy_components(version_map)

          ReleaseMetadataUploader
            .new
            .upload(category, tag_name, release_metadata)
        end

        def tag_name
          raise NotImplementedError
        end

        def version_map
          raise NotImplementedError
        end

        def packager_project
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
