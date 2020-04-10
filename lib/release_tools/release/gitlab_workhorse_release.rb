# frozen_string_literal: true

module ReleaseTools
  module Release
    class GitlabWorkhorseRelease
      extend Forwardable

      include ::SemanticLogger::Loggable

      attr_reader :version, :options

      def_delegator :version, :tag

      def initialize(version, opts = {})
        @version = version_class.new(version)
        @options = opts
      end

      def execute
        if SharedStatus.dry_run?
          logger.warn("Cannot run a release in dry-run mode", project: project, version: version)
          return
        end

        prepare_release
        before_execute_hook
        execute_release
        after_execute_hook
        after_release
      end

      private

      def client
        if SharedStatus.security_release?
          ReleaseTools::GitlabDevClient
        else
          ReleaseTools::GitlabClient
        end
      end

      # Overridable
      def project
        ReleaseTools::Project::GitlabWorkhorse
      end

      def prepare_release
        logger.info("Preparing stable branch", project: project, branch: stable_branch)

        ensure_branch_exists(stable_branch, base: stable_branch_base)
      end

      def ensure_branch_exists(branch_name, base:)
        return if client.find_branch(stable_branch, project)

        client.create_branch(branch_name, base, project)
      end

      # Overridable
      def stable_branch_base
        master_branch
      end

      # Overridable
      def before_execute_hook
        return if version.rc?

        ReleaseTools::Changelog::ManagerApi.new(client, project, 'CHANGELOG', exclude_date: true)
          .release(version)
      rescue ReleaseTools::Changelog::NoChangelogError => ex
        logger.error('Changelog update failed', project: project, version: version, path: ex.changelog_path)
      end

      def execute_release
        if client.find_tag(project, tag)
          logger.warn('Tag already exists, skipping', name: tag)
          return
        end

        return if SharedStatus.dry_run?

        bump_versions(stable_branch)

        create_tag(tag, stable_branch)

        Slack::TagNotification.release(project, version)
      end

      def master_branch
        'master'
      end

      def stable_branch
        version.stable_branch
      end

      # Overridable
      def after_execute_hook
        true
      end

      def after_release
        true
      end

      # Overridable
      def version_class
        Version
      end

      # Overridable
      def bump_versions(ref)
        bump_version('VERSION', version, ref)
      end

      def bump_version(file_name, version, ref)
        file_contents = client.file_contents(project, file_name, ref)
        return if file_contents.chomp == version

        logger.info('Bumping version', file_name: file_name, version: version)

        client.edit_file(project, file_name, ref, "#{version}\n", "Update #{file_name} to #{version}")
      end

      def create_tag(tag, ref, message: nil)
        logger.info('Creating tag', name: tag)

        client.create_tag(project, tag, ref, message: message)
      end
    end
  end
end
