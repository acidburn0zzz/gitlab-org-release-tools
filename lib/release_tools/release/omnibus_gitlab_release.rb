# frozen_string_literal: true

module ReleaseTools
  module Release
    class OmnibusGitlabRelease < GitlabBasedRelease
      class TemplateFileDoesNotExistError < StandardError; end
      class VersionStringNotFoundError < StandardError; end

      # Number of minutes we will be able to reuse the same security repository.
      SECURITY_REPO_GRACE_PERIOD = 24 * 60 * 60

      private

      def after_release
        repository.ensure_branch_exists(stable_branch)
        repository.ensure_branch_exists(master_branch)
        push_ref('branch', stable_branch)
        push_ref('branch', master_branch)

        super
      end

      def before_execute_hook
        repository.ensure_branch_exists(stable_branch)
        compile_changelog
      end

      def compile_changelog
        return if version.rc? || version.ee?

        logger.info('Compiling changelog', version: version)

        ReleaseTools::Changelog::Manager.new(repository.path, 'CHANGELOG.md').release(version)
      rescue ReleaseTools::Changelog::NoChangelogError => ex
        logger.error('Changelog update failed', version: version, path: ex.changelog_path)
      end

      def project
        ReleaseTools::Project::OmnibusGitlab
      end

      def release_name
        version.ee? ? 'omnibus-gitlab-ee' : 'omnibus-gitlab-ce'
      end

      def version_class
        ReleaseTools::OmnibusGitlabVersion
      end

      def bump_versions
        mapping = {}

        version_files.each do |file|
          file_path = File.join(repository.path, file)

          ensure_version_file_exists!(file_path)

          version = read_file_from_gitlab_repo(file)
          mapping[file] = version

          bump_version(file, version)
        end

        release_metadata.add_auto_deploy_components(mapping)
      end

      def version_files
        files = %w[
          GITALY_SERVER_VERSION
          GITLAB_PAGES_VERSION
          GITLAB_SHELL_VERSION
          GITLAB_WORKHORSE_VERSION
          GITLAB_ELASTICSEARCH_INDEXER_VERSION
        ]

        files << 'VERSION' # Always update VERSION last
      end
    end
  end
end
