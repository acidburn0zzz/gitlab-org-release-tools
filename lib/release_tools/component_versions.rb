# frozen_string_literal: true

module ReleaseTools
  class ComponentVersions
    class VersionNotFoundError < StandardError; end

    include ::SemanticLogger::Loggable

    FILES = [
      Project::Gitaly.version_file,
      Project::GitlabElasticsearchIndexer.version_file,
      Project::GitlabPages.version_file,
      Project::GitlabShell.version_file,
      Project::GitlabWorkhorse.version_file
    ].freeze

    GEMS = [
      Project::GitlabMailroom
    ].freeze

    def self.get(project, commit_id)
      versions = { 'VERSION' => commit_id }

      FILES.each_with_object(versions) do |file, memo|
        memo[file] = get_component(project, commit_id, file)
      end

      gemfile_lock = client.file_contents(client.project_path(project), 'Gemfile.lock', commit_id)
      GEMS.each_with_object(versions) do |gem, memo|
        memo[gem.version_file] = version_string_from_gemfile(gemfile_lock, gem.gem_name).chomp
      end

      logger.info({ project: project }.merge(versions))

      versions
    end

    def self.get_component(project, commit_id, file)
      client
        .file_contents(client.project_path(project), file, commit_id)
        .chomp
    end

    def self.version_string_from_gemfile(gemfile_lock, gem_name)
      lock_parser = Bundler::LockfileParser.new(gemfile_lock)
      spec = lock_parser.specs.find { |x| x.name == gem_name.to_s }

      raise VersionNotFoundError.new("Unable to find version for gem `#{gem_name}`") if spec.nil?

      version = spec.version.to_s

      logger.trace("#{gem_name} version", version: version)

      version
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
        next if filename == 'MAILROOM_VERSION'

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
        next if filename == 'MAILROOM_VERSION'

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
        "/ci_files/variables.yml",
        target_branch
      ).chomp
      cng_variables = YAML.safe_load(variables_file)

      helm_compatible_versions = version_map.dup
      gitlab_version = helm_compatible_versions.delete('VERSION')

      %w[GITLAB_VERSION GITLAB_REF_SLUG GITLAB_ASSETS_TAG].each do |component|
        helm_compatible_versions[component] = gitlab_version
      end

      helm_compatible_versions.any? do |component, new_version|
        chart_component_version = cng_variables['variables'][component]

        if component == 'MAILROOM_VERSION'
          new_version != chart_component_version
        else
          new_chart_component_version = ReleaseTools::Version.new(new_version)
          if new_chart_component_version.valid?
            new_chart_component_version.tag != chart_component_version
          else
            new_chart_component_version != chart_component_version
          end
        end
      end
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
