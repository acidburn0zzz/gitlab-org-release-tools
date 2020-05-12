# frozen_string_literal: true

require_relative '../support/ubi_helper'

module ReleaseTools
  module Release
    class CNGImageRelease < GitlabBasedRelease
      include ReleaseTools::Support::UbiHelper

      def project
        Project::CNGImage
      end

      def version_class
        ReleaseTools::CNGVersion
      end

      def release_name
        if version.ee? && options[:ubi]
          'cng-ee-ubi'
        elsif version.ee?
          'cng-ee'
        else
          'cng-ce'
        end
      end

      def tag
        if options[:ubi] && ubi?(version)
          ubi_tag(version, options[:ubi_version])
        else
          super
        end
      end

      private

      def gemfile
        @gemfile ||= ReleaseTools::GemfileParser.new(
          File.read(File.join(options[:gitlab_repo_path], 'Gemfile.lock'))
        )
      end

      def bump_versions
        logger.trace('bump versions')
        target_file = File.join(repository.path, 'ci_files/variables.yml')
        versions = component_versions

        release_metadata.add_auto_deploy_components(versions)

        yaml_contents = YAML.load_file(target_file)
        yaml_contents['variables'].merge!(versions)

        File.open(target_file, 'w') do |f|
          f.write(YAML.dump(yaml_contents))
        end

        # It's expected that the UBI image tag will have nothing to commit
        return if options[:ubi] && !repository.changes?(paths: 'ci_files/variables.yml')

        repository.commit(target_file, message: "Update #{target_file} for #{version}")
      end

      def component_versions
        gitlab_version = version_string(version)

        # These components always track the GitLab release version
        components = {
          'GITLAB_VERSION' => gitlab_version,
          'GITLAB_REF_SLUG' => gitlab_version,
          'GITLAB_ASSETS_TAG' => gitlab_version
        }

        # These components specify their versions independently in files
        #
        # NOTE: We do not yet support GitLab Pages
        [
          ReleaseTools::Project::Gitaly,
          ReleaseTools::Project::GitlabElasticsearchIndexer,
          ReleaseTools::Project::GitlabShell,
          ReleaseTools::Project::GitlabWorkhorse
        ].collect(&:version_file).each { |file| components[file] = version_string_from_file(file) }

        # Gems specify their version in Gemfile.lock
        ReleaseTools::Project::GitlabEe.gems.each_pair do |name, variable|
          components[variable] = gemfile.gem_version(name.to_s)
        end

        logger.trace('Component versions', components: components)

        components
      end
    end
  end
end
