# frozen_string_literal: true

module ReleaseTools
  module Services
    # Automatically updates component versions to their latest passing refs
    class ComponentUpdateService
      include ::SemanticLogger::Loggable

      # The project that receives updated component info
      TARGET_PROJECT = ReleaseTools::Project::GitlabEe

      COMPONENTS = [
        Project::Gitaly,
        Project::GitlabElasticsearchIndexer,
        Project::GitlabPages,
        Project::GitlabShell,
        Project::GitlabWorkhorse
      ].freeze

      attr_reader :target_branch

      def initialize(target_branch)
        @target_branch = target_branch
      end

      def execute
        latest_versions = find_versions
        logger.debug('Searching component versions', log_data(latest_versions))

        update_version(latest_versions) if versions_changed?(latest_versions)
      end

      private

      def gitlab_client
        ReleaseTools::GitlabClient
      end

      def latest_successful_ref(project)
        ReleaseTools::Commits.new(project, client: gitlab_client).latest_successful.id
      end

      def versions_changed?(versions)
        component_versions = ComponentVersions.get_omnibus_compat_versions(target_branch)

        versions.any? do |filename, version|
          component_versions[filename].chomp != version
        end
      end

      def find_versions
        COMPONENTS.each_with_object({}) do |component, versions|
          next unless ::ReleaseTools::Feature.enabled?(:"auto_deploy_#{component.name.demodulize.underscore}")

          versions[component.version_file] = latest_successful_ref(component)
        end
      end

      def update_version(versions)
        logger.info('Updating component versions', log_data(versions))
        return if SharedStatus.dry_run?

        actions = versions.map do |filename, version|
          {
            action: 'update',
            file_path: "/#{filename}",
            content: "#{version}\n"
          }
        end

        gitlab_client.create_commit(
          gitlab_client.project_path(TARGET_PROJECT),
          target_branch,
          'Update component versions',
          actions
        )
      end

      def log_data(data = {})
        data.merge(branch: target_branch)
      end
    end
  end
end
