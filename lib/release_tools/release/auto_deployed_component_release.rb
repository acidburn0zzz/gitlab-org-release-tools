# frozen_string_literal: true

module ReleaseTools
  module Release
    # AutoDeployedComponentRelease implements the life cycle of a
    # GitLab component subject to auto-deployment from master
    #
    # Stable branch creation is based on the version ref provided by
    # the gitlab repository.
    #
    # This will guarantee that new monthly releases are tagged from
    # the last commit that reached production.
    #
    # In case of a patch release, it will be tagged from the stable
    # branch HEAD.
    #
    # Engineers are still free to tag RCs manually
    class AutoDeployedComponentRelease < GitlabBasedRelease
      class TaggingNotAllowed < StandardError; end

      def stable_branch_base
        @stable_branch_base ||= version_string_from_file(project.version_file)
      end

      def stable_branch
        return master_branch if tag_from_master_head?

        super
      end

      def tag_from_master_head?
        options[:tag_from_master_head]
      end

      def check_required_parameters!
        return super unless tag_from_master_head?

        raise TaggingNotAllowed, "only RC can be tagged from master" unless version.rc?
      end

      def prepare_release
        return super unless tag_from_master_head?

        logger.info('Preparing a master release', project: project, version: version)
        repository.pull_from_all_remotes(master_branch)
      end

      def before_execute_hook
        compile_changelog
      end

      def after_execute_hook
        return unless version.monthly?

        repository.merge(stable_branch, into: master_branch, no_ff: true)
        push_ref('branch', master_branch)

        repository.ensure_branch_exists(stable_branch, base: stable_branch_base)
      end

      def compile_changelog
        return if version.rc?

        ReleaseTools::Changelog::Manager.new(repository.path, 'CHANGELOG.md', include_date: false)
          .release(version, skip_master: version.monthly?)
      rescue ReleaseTools::Changelog::NoChangelogError => ex
        logger.error('Changelog update failed', project: project, version: version, path: ex.changelog_path)
      end
    end
  end
end
