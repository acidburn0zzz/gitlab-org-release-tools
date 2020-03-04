# frozen_string_literal: true

module ReleaseTools
  module AutoDeploy
    module Tagger
      class Omnibus
        include ::SemanticLogger::Loggable

        PROJECT = Project::OmnibusGitlab
        TAG_FORMAT = '%<major>d.%<minor>d.%<timestamp>s+%<gitlab_ref>.11s.%<packager_ref>.11s'

        def initialize(target_branch, version_map)
          @target_branch = target_branch
          @version_map = version_map

          @major, @minor = target_branch.split('-', 3).take(2)
        end

        def tag_name
          commit = branch_head

          @tag_name ||= format(
            TAG_FORMAT,
            major: @major,
            minor: @minor,
            timestamp: timestamp(commit.created_at),
            gitlab_ref: @version_map.fetch('VERSION'),
            packager_ref: commit.id
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
          logger.info('Creating Omnibus tag', name: tag_name, target: branch_head.id)

          return if SharedStatus.dry_run?

          client.create_tag(
            client.project_path(PROJECT),
            tag_name,
            branch_head.id,
            tag_message
          )
        end

        private

        def branch_head
          @branch_head ||= client.commit(PROJECT, ref: @target_branch)
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
