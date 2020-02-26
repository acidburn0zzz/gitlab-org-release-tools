# frozen_string_literal: true

module ReleaseTools
  class PassingBuild
    include ::SemanticLogger::Loggable

    attr_reader :ref

    def initialize(ref)
      @project = ReleaseTools::Project::GitlabEe
      @ref = ref
    end

    def execute(trigger: false)
      commits = ReleaseTools::Commits.new(@project, ref: ref)

      commit =
        if SharedStatus.security_release?
          # Passing builds on dev are few and far between; for a security
          # release we'll just use the latest commit on the branch
          commits.latest
        else
          commits.latest_successful_on_build
        end

      if commit.nil?
        raise "Unable to find a passing #{@project} build for `#{ref}` on dev"
      end

      @omnibus_version_map = ReleaseTools::ComponentVersions.get_omnibus_compat_versions(commit.id)
      @cng_version_map = ReleaseTools::ComponentVersions.get_cng_compat_versions(commit.id)

      trigger_build if trigger
    end

    def trigger_build
      if ref.match?(/\A(?:security\/)?\d+-\d+-auto-deploy-\d+\z/)
        update_projects_for_autodeploy
      else
        logger.fatal('Invalid ref for passing build trigger', ref: ref)
      end
    end

    def tag(target_commit)
      tag_name = ReleaseTools::AutoDeploy::Naming.tag(
        timestamp: target_commit.created_at.to_s,
        packager_ref: target_commit.id,
        ee_ref: @omnibus_version_map['VERSION']
      )

      tag_message = +"Auto-deploy #{tag_name}\n\n"
      tag_message << @omnibus_version_map
        .map { |component, version| "#{component}: #{version}" }
        .join("\n")

      tag_omnibus(tag_name, tag_message, target_commit)
      tag_deployer(tag_name, tag_message, 'master')
    end

    private

    def update_projects_for_autodeploy
      ReleaseTools::ComponentVersions.update_cng(ref, @cng_version_map)
      ReleaseTools::ComponentVersions.update_omnibus(ref, @omnibus_version_map)

      project = ReleaseTools::Project::OmnibusGitlab
      if project_changes?(project)
        commit = ReleaseTools::Commits
          .new(project, ref: ref)
          .latest

        id = tag(commit)
        logger.warn('Tagging', project: project, tag: id)
      else
        logger.warn("No changes to #{project}, nothing to tag")
      end
    end

    def project_changes?(project)
      refs = GitlabClient.commit_refs(project, ref)

      # When our auto-deploy branch `ref` has no associated tags, then there
      # have been changes on the branch since we last tagged it, and should be
      # considered changed
      refs.none? { |ref| ref.type == 'tag' }
    end

    def tag_omnibus(name, message, commit)
      project = ReleaseTools::Project::OmnibusGitlab

      logger.info('Creating project tag', project: project, name: name)

      client =
        if SharedStatus.security_release?
          ReleaseTools::GitlabDevClient
        else
          ReleaseTools::GitlabClient
        end

      client.create_tag(client.project_path(project), name, commit.id, message)
    end

    def tag_deployer(name, message, ref)
      project = ReleaseTools::Project::Deployer

      logger.info('Creating project tag', project: project, name: name)

      ReleaseTools::GitlabOpsClient
        .create_tag(project.path, name, ref, message)
    end
  end
end
