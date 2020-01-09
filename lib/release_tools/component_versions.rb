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

    GEMS = [
      Project::GitlabMailroom.gem_name
    ].freeze

    def self.get(project, commit_id)
      versions = { 'VERSION' => commit_id }

      FILES.each_with_object(versions) do |file, memo|
        memo[file] = get_component(project, commit_id, file)
      end

      GEMS.each_with_object(versions) do |gem_name, memo|
        memo[gem_name] = client
          .version_string_from_gemfile(client.file_contents(client.project_path(project), 'Gemfile.lock', commit_id), gem_name)
          .chomp
      end

      logger.info({ project: project }.merge(versions))

      versions
    end

    def self.get_component(project, commit_id, file)
      client
        .file_contents(client.project_path(project), file, commit_id)
        .chomp
    end

    def self.update_cng(target_branch, version_map)
      return if SharedStatus.dry_run?

      variables_file = client.file_contents(
        client.project_path(ReleaseTools::Project::CNGImage),
        "ci_files/variables.yml",
        target_branch
      ).chomp
      cng_variables = YAML.safe_load(variables_file)
      version_map.each do |component, new_version|
        if component == 'mail_room'
          component = 'MAILROOM_VERSION'
        end

        cng_variables['variables'].each do |c, old_version|
          if component == 'VERSION'
            cng_variables['variables']['GITLAB_VERSION'] = new_version
            cng_variables['variables']['GITLAB_REF_SLUG'] = new_version
            cng_variables['variables']['GITLAB_ASSETS_TAG'] = new_version
          end
          next if component != c

          logger.trace('Finding changes', component: component, old_version: old_version, new_version: "v#{new_version}")

          # I don't like this...
          if component == 'MAILROOM_VERSION'
            cng_variables['variables'][component] = new_version
          else
            cng_variables['variables'][component] = "v#{new_version}"
          end
        end
      end

      actions =
        {
          action: 'update',
          file_path: "ci_files/variables.yml",
          content: cng_variables.to_yaml
        }

      client.create_commit(
        client.project_path(ReleaseTools::Project::CNGImage),
        target_branch,
        'Update component versions',
        [actions]
      )
    end

    def self.update_omnibus(target_branch, version_map)
      return if SharedStatus.dry_run?

      actions = version_map.map do |filename, contents|
        next if filename == 'mail_room'

        logger.trace('Finding changes', filename: filename, content: contents)
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

    def self.omnibus_version_changes?(target_branch, version_map)
      version_map.any? do |filename, contents|
        next if filename == 'mail_room'

        client.file_contents(
          client.project_path(ReleaseTools::Project::OmnibusGitlab),
          "/#{filename}",
          target_branch
        ).chomp != contents
      end
    end

    def self.cng_version_changes?(target_branch, version_map)
      variables_file = client.file_contents(
        client.project_path(ReleaseTools::Project::CNGImage),
        "ci_files/variables.yml",
        target_branch
      ).chomp
      cng_variables = YAML.safe_load(variables_file)
      version_map.each do |component, new_version|
        if component == 'mail_room'
          component = 'MAILROOM_VERSION'
        end

        cng_variables['variables'].each do |c, old_version|
          next if component != c

          logger.trace('Finding changes', component: component, old_version: old_version, new_version: "v#{new_version}")

          if component == 'MAILROOM_VERSION'
            next if old_version == new_version
          end

          return true if old_version != "v#{new_version}"
        end
      end

      false
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
