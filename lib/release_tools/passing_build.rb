# frozen_string_literal: true

module ReleaseTools
  class PassingBuild
    include ::SemanticLogger::Loggable

    attr_reader :project, :ref

    def initialize(project, ref)
      @project = project
      @ref = ref
    end

    def execute(args)
      commits = ReleaseTools::Commits.new(project, ref: ref)

      commit =
        if SharedStatus.security_release?
          # Passing builds on dev are few and far between; for a security
          # release we'll just use the latest commit on the branch
          commits.latest
        else
          commits.latest_successful_on_build
        end

      if commit.nil?
        raise "Unable to find a passing #{project} build for `#{ref}` on dev"
      end

      @version_map = ReleaseTools::ComponentVersions.get(project, commit.id)

      trigger_build if args.trigger_build
    end

    def trigger_build
      if ref.match?(/\A(?:security\/)?\d+-\d+-auto-deploy-\d+\z/)
        update_omnibus_for_autodeploy
      else
        logger.fatal('Invalid ref for passing build trigger', ref: ref)
      end
    end

    def tag(target_commit)
      tag_name = ReleaseTools::AutoDeploy::Naming.tag(
        timestamp: target_commit.created_at.to_s,
        omnibus_ref: target_commit.id,
        ee_ref: @version_map['VERSION']
      )

      tag_message = +"Auto-deploy #{tag_name}\n\n"
      tag_message << @version_map
        .map { |component, version| "#{component}: #{version}" }
        .join("\n")

      tag_omnibus(tag_name, tag_message, target_commit)
      tag_deployer(tag_name, tag_message, 'master')
    end

    private

    def update_omnibus_for_autodeploy
      if ReleaseTools::ComponentVersions.omnibus_version_changes?(ref, @version_map)
        commit = update_omnibus

        tag(commit)
      elsif omnibus_changes?
        commit = ReleaseTools::Commits
          .new(ReleaseTools::Project::OmnibusGitlab, ref: ref)
          .latest

        tag(commit)
      else
        logger.warn('No changes to component versions or Omnibus, nothing to tag')
      end
    end

    def omnibus_changes?
      project = ReleaseTools::Project::OmnibusGitlab
      refs = GitlabClient.commit_refs(project, ref)

      # When our auto-deploy branch `ref` has no associated tags, then there
      # have been changes on the branch since we last tagged it, and should be
      # considered changed
      refs.none? { |ref| ref.type == 'tag' }
    end

    def update_omnibus
      commit = ReleaseTools::ComponentVersions.update_omnibus(ref, @version_map)

      url = commit_url(ReleaseTools::Project::OmnibusGitlab, commit.id)
      logger.info('Updated Omnibus versions', commit_url: url)

      commit
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

    # See https://gitlab.com/gitlab-org/gitlab-foss/issues/25392
    def commit_url(project, id)
      if SharedStatus.security_release?
        "https://dev.gitlab.org/#{project}/commit/#{id}"
      else
        "https://gitlab.com/#{project}/commit/#{id}"
      end
    end
  end
end
