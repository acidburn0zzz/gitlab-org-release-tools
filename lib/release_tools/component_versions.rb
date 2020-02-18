# frozen_string_literal: true

module ReleaseTools
  class ComponentVersions
    include ::SemanticLogger::Loggable

    FILES = [
      Project::Gitaly.version_file,
      Project::GitlabElasticsearchIndexer.version_file,
      Project::GitlabPages.version_file,
      Project::GitlabShell.version_file,
      Project::GitlabWorkhorse.version_file
    ].freeze

    def self.get_omnibus_compat_versions(project, commit_id)
      versions = { 'VERSION' => commit_id }

      FILES.each_with_object(versions) do |file, memo|
        memo[file] = get_component(project, commit_id, file)
      end

      logger.info('Omnibus Versions', { project: project }.merge(versions))

      versions
    end

    def self.get_cng_compat_versions(project, commit_id)
      versions = get_omnibus_compat_versions(project, commit_id)

      versions = sanitize_cng_versions(versions)

      gemfile = GemfileParser.new(
        client.file_contents(
          client.project_path(project),
          'Gemfile.lock',
          commit_id
        )
      )

      Project::GitlabEe.gems.each do |gem_name, variable|
        versions[variable] = gemfile.gem_version(gem_name)
      end

      logger.info('CNG Versions', { project: project }.merge(versions))

      versions
    end

    def self.sanitize_cng_versions(versions)
      versions['GITLAB_VERSION'] = versions['GITLAB_ASSETS_TAG'] = versions.delete('VERSION')

      versions.each_pair do |component, version|
        # If it looks like SemVer, assume it's a tag, which we prepend with `v`
        if version.match?(/\A\d+\.\d+\.\d+\z/)
          versions[component] = "v#{version}"
        end
      end

      versions
    end

    def self.get_component(project, commit_id, file)
      client
        .file_contents(client.project_path(project), file, commit_id)
        .chomp
    end

    def self.update_cng(target_branch, version_map)
      return if SharedStatus.dry_run?

      old_variables = cng_variables(target_branch)
      new_variables = old_variables.merge(version_map)

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
    rescue ::Gitlab::Error::Error => ex
      logger.fatal(
        'Failed to commit CNG version changes',
        target: target_branch,
        error_code: ex.response_status,
        error_message: ex.response_message
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
      end

      client.create_commit(
        client.project_path(ReleaseTools::Project::OmnibusGitlab),
        target_branch,
        'Update component versions',
        actions
      )
    rescue ::Gitlab::Error::Error => ex
      logger.fatal(
        'Failed to commit Omnibus version changes',
        target: target_branch,
        error_code: ex.response_status,
        error_message: ex.message
      )
    end

    def self.cng_version_changes?(target_branch, version_map)
      variables_file = client.file_contents(
        client.project_path(ReleaseTools::Project::CNGImage),
        '/ci_files/variables.yml',
        target_branch
      ).chomp

      old_versions = YAML.safe_load(variables_file).fetch('variables')

      version_map.any? do |component, version|
        old_versions[component] != version
      end
    rescue ::Gitlab::Error::Error => ex
      logger.warn(
        'Failed to find CNG version file',
        target: target_branch,
        error_code: ex.response_status,
        error_message: ex.message
      )

      false
    end

    def self.omnibus_version_changes?(target_branch, version_map)
      version_map.any? do |filename, contents|
        client.file_contents(
          client.project_path(ReleaseTools::Project::OmnibusGitlab),
          "/#{filename}",
          target_branch
        ).chomp != contents
      end
    rescue ::Gitlab::Error::Error => ex
      logger.warn(
        'Failed to find Omnibus version file',
        target: target_branch,
        error_code: ex.response_status,
        error_message: ex.message
      )

      false
    end

    def self.cng_variables(target_branch)
      variables = client.file_contents(
        client.project_path(ReleaseTools::Project::CNGImage),
        '/ci_files/variables.yml',
        target_branch
      ).chomp

      YAML.safe_load(variables).fetch('variables')
    end

    def self.client
      if SharedStatus.security_release?
        ReleaseTools::GitlabDevClient
      else
        ReleaseTools::GitlabClient
      end
    end
  end
end
