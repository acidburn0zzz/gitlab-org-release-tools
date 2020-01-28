# frozen_string_literal: true

require_relative '../support/ubi_helper'

module ReleaseTools
  module Services
    # After a release, sync branches and tags across all remotes
    #
    # If the `security_remote` feature flag is enabled, it will push to Security
    # in addition to Canonical and Build.
    class SyncRemotesService
      include ::SemanticLogger::Loggable
      include ReleaseTools::Support::UbiHelper

      MASTER_BRANCH = 'master'

      def initialize(version)
        @version = version.to_ce
        @omnibus = OmnibusGitlabVersion.new(@version.to_omnibus)
      end

      def execute
        if Feature.disabled?(:publish_git)
          logger.warn('The `publish_git` feature is disabled.')
          return
        end

        sync_branches(
          Project::GitlabEe,
          @version.stable_branch(ee: true),
          ReleaseTools::AutoDeployBranch.current,
          MASTER_BRANCH
        )
        sync_branches(
          Project::GitlabCe,
          @version.stable_branch(ee: false),
          MASTER_BRANCH
        )
        sync_branches(Project::OmnibusGitlab, *[
          @omnibus.to_ee.stable_branch,
          @omnibus.to_ce.stable_branch,
          ReleaseTools::AutoDeployBranch.current,
          MASTER_BRANCH
        ].uniq) # Omnibus uses a single branch post-12.2

        # There's no need for a separate CNG UBI stable branch. It is the same as EE branch.
        sync_branches(Project::CNGImage, @version.to_ce.stable_branch, @version.to_ee.stable_branch)

        sync_tags(Project::GitlabEe, @version.tag(ee: true))
        sync_tags(Project::GitlabCe, @version.tag(ee: false))
        sync_tags(Project::OmnibusGitlab, @omnibus.to_ee.tag, @omnibus.to_ce.tag)
        sync_tags(Project::CNGImage, @version.to_ce.tag, @version.to_ee.tag, ubi_tag(@version.to_ee))
      end

      # Sync project release branches across all remotes
      #
      # For each branch name in `branches`, it will:
      #   1. Clone the branch from Canonical
      #   2. Fetch the branch from Build
      #   3. Merge Dev into Canonical
      #   4. Push changes to all remotes if the merge is successful
      def sync_branches(project, *branches)
        sync_remotes = remotes_to_sync(project).fetch(:remotes)
        remotes_size = remotes_to_sync(project).fetch(:size)

        if sync_remotes.size < remotes_size
          logger.fatal("Expected at least #{remotes_size} remotes, got #{sync_remotes.size}", project: project, remotes: sync_remotes)
          return
        end

        branches.each do |branch|
          repository = RemoteRepository.get(sync_remotes, global_depth: 50, branch: branch)

          repository.fetch(branch, remote: :dev)

          result = repository.merge("dev/#{branch}", branch, no_ff: true)

          if result.status.success?
            logger.info('Pushing branch to remotes', project: project, name: branch, remotes: sync_remotes.keys)
            repository.push_to_all_remotes(branch)
          else
            logger.fatal('Failed to sync branch', project: project, name: branch, output: result.output)
          end
        end
      end

      def sync_tags(project, *tags)
        sync_remotes = remotes_to_sync(project).fetch(:remotes)
        repository = RemoteRepository.get(sync_remotes, global_depth: 50)

        tags.each do |tag|
          logger.info('Fetching tag', project: project, name: tag)
          repository.fetch("refs/tags/#{tag}", remote: :dev)

          logger.info('Pushing tag to remotes', project: project, name: tag, remotes: sync_remotes.keys)
          repository.push_to_all_remotes(tag)
        end
      end

      private

      def remotes_to_sync(project)
        if Feature.enabled?(:security_remote)
          { remotes: project::REMOTES.slice(:canonical, :dev, :security), size: 3 }
        else
          { remotes: project.remotes.slice(:canonical, :dev), size: 2 }
        end
      end
    end
  end
end
