# frozen_string_literal: true

module ReleaseTools
  module AutoDeploy
    module Tagger
      class Omnibus
        include ::SemanticLogger::Loggable

        PROJECT = Project::OmnibusGitlab
        DEPLOYER = Project::Deployer

        TAG_FORMAT = '%<major>d.%<minor>d.%<timestamp>s+%<gitlab_ref>.11s.%<packager_ref>.11s'

        def initialize(target_branch, version_map)
          @target_branch = target_branch
          @version_map = version_map

          @major, @minor = target_branch.split('-', 3).take(2)

          raise ArgumentError, "Unable to determine version from #{target_branch}" unless @major && @minor
        end

        def tag_name
          @tag_name ||= format(
            TAG_FORMAT,
            major: @major,
            minor: @minor,
            timestamp: timestamp(branch_head.created_at),
            gitlab_ref: @version_map.fetch('VERSION'),
            packager_ref: branch_head.id
          )
        end

        def tag_message
          @tag_message ||=
            begin
              tag_message = +"Auto-deploy Omnibus #{tag_name}\n\n"
              tag_message << @version_map
                .map { |component, version| "#{component}: #{version}" }
                .join("\n")
            end
        end

        def tag!
          unless changes?
            logger.warn("No changes to Omnibus, nothing to tag", target: @target_branch)

            return
          end

          logger.info('Creating Omnibus tag', name: tag_name, target: branch_head.id)

          return if SharedStatus.dry_run?

          tag = client.create_tag(
            client.project_path(PROJECT),
            tag_name,
            branch_head.id,
            tag_message
          )

          tag_deployer!(tag)

          tag
        rescue ::Gitlab::Error::Error => ex
          logger.fatal(
            "Failed to tag Omnibus",
            name: tag_name,
            target: branch_head.id,
            error_code: ex.response_status,
            error_message: ex.message
          )
        end

        def tag_deployer!(tag)
          logger.info('Tagging Deployer', name: tag.name)

          return if SharedStatus.dry_run?

          ReleaseTools::GitlabOpsClient.create_tag(
            DEPLOYER.path,
            tag.name,
            'master',
            tag.message
          )
        rescue ::Gitlab::Error::Error => ex
          logger.fatal(
            "Failed to tag Deployer",
            name: tag.name,
            target: 'master',
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
      end
    end
  end
end
