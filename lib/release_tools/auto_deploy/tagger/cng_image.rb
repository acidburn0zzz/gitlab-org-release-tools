# frozen_string_literal: true

module ReleaseTools
  module AutoDeploy
    module Tagger
      class CNGImage
        include ::SemanticLogger::Loggable
        include ReleaseMetadataTracking

        PROJECT = Project::CNGImage
        HELM = Project::HelmGitlab

        TAG_FORMAT = '%<major>d.%<minor>d.%<timestamp>s+%<gitlab_ref>.11s'

        attr_reader :version_map, :target_branch

        def initialize(target_branch, version_map)
          @target_branch = target_branch
          @version_map = version_map

          @major, @minor = target_branch.split('-', 3).take(2)

          raise ArgumentError, "Unable to determine version from #{target_branch}" unless @major && @minor

          @helm_tagger = ReleaseTools::AutoDeploy::Tagger::Helm.new(@target_branch, @version_map)
        end

        def tag_name
          @tag_name ||= format(
            TAG_FORMAT,
            major: @major,
            minor: @minor,
            timestamp: timestamp(branch_head.created_at),
            gitlab_ref: gitlab_ref
          )
        end

        def tag_message
          @tag_message ||=
            begin
              tag_message = +"Auto-deploy CNG #{tag_name}\n\n"
              tag_message << @version_map
                .map { |component, version| "#{component}: #{version}" }
                .join("\n")
            end
        end

        def tag!
          unless changes?
            logger.warn("No changes to CNG, nothing to tag", target: @target_branch)

            return
          end

          logger.info('Creating CNG tag', name: tag_name, target: branch_head.id)

          return if SharedStatus.dry_run?

          upload_version_data('cng')

          tag = client.create_tag(
            client.project_path(PROJECT),
            tag_name,
            branch_head.id,
            tag_message
          )

          @helm_tagger.tag!(tag_name)

          tag
        rescue ::Gitlab::Error::Error => ex
          logger.fatal(
            "Failed to tag CNG",
            name: tag_name,
            target: branch_head.id,
            error_code: ex.response_status,
            error_message: ex.message
          )
        end

        private

        def branch_head
          @branch_head ||= client.commit(PROJECT, ref: @target_branch)
        end

        def changes?
          refs = client.commit_refs(PROJECT, @target_branch)

          # When our target branch has no associated tags, then there have been
          # changes on the branch since we last tagged it, and should be
          # considered changed
          refs.none? { |ref| ref.type == 'tag' }
        end

        def timestamp(datetime)
          Time.parse(datetime.to_s).strftime('%Y%m%d%H%M')
        end

        def client
          if SharedStatus.security_release?
            ReleaseTools::GitlabDevClient
          else
            ReleaseTools::GitlabClient
          end
        end

        def packager_name
          'cng-ee'
        end

        def gitlab_ref
          @version_map.fetch('GITLAB_VERSION')
        end

        def packager_ref
          branch_head.id
        end
      end
    end
  end
end
