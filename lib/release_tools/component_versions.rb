# frozen_string_literal: true

module ReleaseTools
  class ComponentVersions
    class VersionNotFoundError < StandardError
      def initialize(gem_name)
        super("Unable to find a version for gem #{gem_name}")
      end
    end

    include ::SemanticLogger::Loggable

    FILES = [
      Project::Gitaly.version_file,
      Project::GitlabElasticsearchIndexer.version_file,
      Project::GitlabPages.version_file,
      Project::GitlabShell.version_file,
      Project::GitlabWorkhorse.version_file
    ].freeze

    GEMS = [
      Project::GitlabEe::Components::Mailroom
    ].freeze

    # Get a Hash of `version_file => version` maps for a project as of a
    # specified commit
    #
    # project - A Project instance (in reality, this is always EE)
    # commit_id - Commit SHA string
    #
    # Examples:
    #
    #   get_omnibus_versions(Project::GitlabEe, '36b70d9ce7c73ca001be48727d35d49813d2cc4f')
    #   => {
    #     "VERSION"=>"36b70d9ce7c73ca001be48727d35d49813d2cc4f",
    #     "GITALY_SERVER_VERSION"=>"1.83.0",
    #     "GITLAB_ELASTICSEARCH_INDEXER_VERSION"=>"2.0.0",
    #     "GITLAB_PAGES_VERSION"=>"1.14.0",
    #     "GITLAB_SHELL_VERSION"=>"11.0.0",
    #     "GITLAB_WORKHORSE_VERSION"=>"8.19.0"
    #   }
    def self.get_omnibus_versions(project, commit_id)
      versions = { 'VERSION' => commit_id }

      FILES.each_with_object(versions) do |file, memo|
        memo[file] = get_component(project, commit_id, file)
      end

      logger.info({ project: project }.merge(versions))

      versions
    end

    # Get a Hash of `component => version` maps for a project as of a specified
    # commit
    #
    # project - Project instance (in reality, this is always EE)
    # commit_id - Commit of the project at which to fetch versions
    #
    # Examples:
    #
    #   get_cng_versions(Project::GitlabEe, '36b70d9ce7c73ca001be48727d35d49813d2cc4f')
    #   => {
    #     "GITLAB_ELASTICSEARCH_INDEXER_VERSION"=>"v2.0.0",
    #     "GITLAB_PAGES_VERSION"=>"v1.14.0",
    #     "GITLAB_SHELL_VERSION"=>"v11.0.0",
    #     "GITLAB_WORKHORSE_VERSION"=>"v8.19.0",#
    #     "GITLAB_ASSETS_TAG"=>"36b70d9ce7c73ca001be48727d35d49813d2cc4f",
    #     "GITLAB_VERSION"=>"36b70d9ce7c73ca001be48727d35d49813d2cc4f",
    #     "GITALY_VERSION"=>"v1.83.0",
    #     "MAILROOM_VERSION"=>"0.10.0"
    #   }
    def self.get_cng_versions(project, commit_id)
      # Start with the Omnibus map
      versions = get_omnibus_versions(project, commit_id)

      # Massage definition variances
      versions['GITLAB_VERSION'] = versions['GITLAB_ASSETS_TAG'] = versions.delete('VERSION')
      versions['GITALY_VERSION'] = versions.delete('GITALY_SERVER_VERSION')

      versions.each_pair do |component, version|
        # If it looks like SemVer, assume it's a tag, which we prepend with `v`
        if version.match?(/\A\d+\.\d+\.\d+\z/)
          versions[component] = "v#{version}"
        end
      end

      # Add required gem versions as defined by the project's Gemfile
      gemfile_lock = client.file_contents(client.project_path(project), 'Gemfile.lock', commit_id)
      GEMS.each do |gem|
        versions[gem.version_file] = version_from_gemfile(gemfile_lock, gem.gem_name).chomp
      end

      logger.info({ project: project }.merge(versions))

      versions
    end

    def self.get_component(project, commit_id, file)
      client
        .file_contents(client.project_path(project), file, commit_id)
        .chomp
    end

    # TODO: Extract to a Gemfile class or something
    def self.version_from_gemfile(gemfile_lock, gem_name)
      lock_parser = ::Bundler::LockfileParser.new(gemfile_lock)
      spec = lock_parser.specs.find { |x| x.name == gem_name }

      raise VersionNotFoundError, gem_name if spec.nil?

      version = spec.version.to_s

      logger.trace('Version from Gemfile.lock', gem: gem_name, version: version)

      version
    end

    def self.update_cng(target_branch, version_map)
      return if SharedStatus.dry_run?

      current_variables = cng_variables(target_branch)
      new_variables = current_variables.merge(version_map)

      action = {
        action: 'update',
        file_path: '/ci_files/variables.yml',
        content: { 'variables' => new_variables }.to_yaml
      }

      client.create_commit(
        client.project_path(ReleaseTools::Project::CNGImage),
        target_branch,
        'Update component versions',
        [action]
      )
    end

    def self.update_omnibus(target_branch, version_map)
      return if SharedStatus.dry_run?

      actions = version_map.map do |filename, contents|
        {
          action: 'update',
          file_path: "/#{filename}",
          content: "#{contents}\n"
        }
      end.compact

      client.create_commit(
        client.project_path(ReleaseTools::Project::OmnibusGitlab),
        target_branch,
        'Update component versions',
        actions
      )
    end

    # Check if Omnibus component versions on the specified branch differ from a
    # given map
    def self.omnibus_version_changes?(target_branch, version_map)
      version_map.any? do |filename, contents|
        client.file_contents(
          client.project_path(ReleaseTools::Project::OmnibusGitlab),
          "/#{filename}",
          target_branch
        ).chomp != contents
      end
    end

    # Check if CNG component versions on the specified branch differ from a
    # given map
    def self.cng_version_changes?(target_branch, version_map)
      current_variables = cng_variables(target_branch)

      version_map.any? do |version_file, version|
        current_variables[version_file] != version
      end
    end

    def self.client
      if SharedStatus.security_release?
        ReleaseTools::GitlabDevClient
      else
        ReleaseTools::GitlabClient
      end
    end

    # Returns a Hash of `variables => version` for CNG image on a specified
    # branch
    def self.cng_variables(target_branch)
      variables_file = client.file_contents(
        client.project_path(ReleaseTools::Project::CNGImage),
        "/ci_files/variables.yml",
        target_branch
      ).chomp

      YAML.safe_load(variables_file).fetch('variables')
    end
  end
end
