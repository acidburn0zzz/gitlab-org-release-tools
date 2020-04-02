# frozen_string_literal: true

module ReleaseTools
  class ComponentVersions
    include ::SemanticLogger::Loggable

    # The project that defines the component versions we're working with
    SOURCE_PROJECT = ReleaseTools::Project::GitlabEe

    # Shorthands for the two packagers this class currently works with
    OmnibusGitlab = ReleaseTools::Project::OmnibusGitlab
    CNGImage = ReleaseTools::Project::CNGImage

    FILES = [
      Project::Gitaly.version_file,
      Project::GitlabElasticsearchIndexer.version_file,
      Project::GitlabPages.version_file,
      Project::GitlabShell.version_file,
      Project::GitlabWorkhorse.version_file
    ].freeze

    def self.client
      if SharedStatus.security_release?
        ReleaseTools::GitlabDevClient
      else
        ReleaseTools::GitlabClient
      end
    end

    def self.get_component(commit_id, file)
      client
        .file_contents(SOURCE_PROJECT, file, commit_id)
        .chomp
    end

    # See https://gitlab.com/gitlab-org/gitlab/issues/16661
    def self.commit_url(project, id)
      if SharedStatus.security_release?
        "https://dev.gitlab.org/#{project.dev_path}/commit/#{id}"
      else
        "https://gitlab.com/#{project.path}/commit/#{id}"
      end
    end

    # Omnibus
    # ----------------------------------------------------------------------

    def self.get_omnibus_compat_versions(commit_id)
      versions = { 'VERSION' => commit_id }

      FILES.each_with_object(versions) do |file, memo|
        memo[file] = get_component(commit_id, file)
      end

      logger.info('Omnibus Versions', versions)

      versions
    end

    def self.omnibus_version_changes?(target_branch, version_map)
      version_map.any? do |filename, contents|
        client.file_contents(
          OmnibusGitlab,
          filename,
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

    def self.update_omnibus(target_branch, version_map)
      unless omnibus_version_changes?(target_branch, version_map)
        return logger.warn('No changes to Omnibus component versions')
      end

      return if SharedStatus.dry_run?

      commit_omnibus(target_branch, version_map)
    end

    def self.commit_omnibus(target_branch, version_map)
      actions = version_map.map do |filename, contents|
        {
          action: 'update',
          file_path: "/#{filename}",
          content: "#{contents}\n"
        }
      end

      commit = client.create_commit(
        OmnibusGitlab,
        target_branch,
        'Update component versions',
        actions
      )

      url = commit_url(OmnibusGitlab, commit.id)
      logger.info('Updated Omnibus versions', commit_url: url)

      commit
    rescue ::Gitlab::Error::Error => ex
      logger.fatal(
        'Failed to commit Omnibus version changes',
        target: target_branch,
        error_code: ex.response_status,
        error_message: ex.message
      )
    end

    # CNG
    # ----------------------------------------------------------------------

    def self.get_cng_compat_versions(commit_id)
      versions = get_omnibus_compat_versions(commit_id)
      versions = sanitize_cng_versions(versions)

      gemfile = GemfileParser.new(
        client.file_contents(
          SOURCE_PROJECT,
          'Gemfile.lock',
          commit_id
        )
      )

      SOURCE_PROJECT.gems.each do |gem_name, variable|
        versions[variable] = gemfile.gem_version(gem_name)
      end

      logger.info('CNG Versions', versions)

      versions
    end

    def self.sanitize_cng_versions(versions)
      versions['GITLAB_VERSION'] = versions['GITLAB_ASSETS_TAG'] = versions.delete('VERSION')

      versions.each_pair do |component, version|
        # If it looks like SemVer, assume it's a tag, which we prepend with `v`
        versions[component] = if version.match?(/\A\h{40}\z/)
                                version
                              else
                                "v#{version}"
                              end
      end

      versions
    end

    def self.cng_version_changes?(target_branch, version_map)
      variables_file = client.file_contents(
        CNGImage,
        'ci_files/variables.yml',
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

    def self.update_cng(target_branch, version_map)
      unless cng_version_changes?(target_branch, version_map)
        return logger.warn('No changes to CNG component versions')
      end

      return if SharedStatus.dry_run?

      commit_cng(target_branch, version_map)
    end

    def self.commit_cng(target_branch, version_map)
      old_variables = cng_variables(target_branch)
      new_variables = old_variables.merge(version_map)

      action = {
        action: 'update',
        file_path: 'ci_files/variables.yml',
        content: { 'variables' => new_variables }.to_yaml
      }

      commit = client.create_commit(
        CNGImage,
        target_branch,
        'Update component versions',
        [action]
      )

      url = commit_url(CNGImage, commit.id)
      logger.info('Updated CNG versions', commit_url: url)

      commit
    rescue ::Gitlab::Error::Error => ex
      logger.fatal(
        'Failed to commit CNG version changes',
        target: target_branch,
        error_code: ex.response_status,
        error_message: ex.response_message
      )
    end

    def self.cng_variables(target_branch)
      variables = client.file_contents(
        CNGImage,
        'ci_files/variables.yml',
        target_branch
      ).chomp

      YAML.safe_load(variables).fetch('variables')
    end
  end
end
