# frozen_string_literal: true

module ReleaseTools
  module Deployments
    # Tracking of deployments using the GitLab API
    class DeploymentTracker
      include ::SemanticLogger::Loggable

      # A regex to use for ensuring that we only track Gitaly deployments for
      # SHAs, not tagged versions.
      GITALY_SHA_REGEX = /\A[0-9a-f]{40}\z/.freeze

      # A regex that matches Gitaly tagged releases, such as "12.8.1".
      GITALY_TAGGED_RELEASE_REGEX = /\A\d+\.\d+\.\d+(-rc\d+)?\z/.freeze

      # The deployment statuses that we support.
      DEPLOYMENT_STATUSES = Set.new(%w[success failed]).freeze

      # The ref to use for recording Gitaly deployments
      GITALY_DEPLOY_REF = 'master'

      # A deployment created using the GitLab API
      Deployment = Struct.new(:project, :id, :status) do
        def success?
          status == 'success'
        end
      end

      # The name of the staging environment of GitLab.com.
      STAGING = 'gstg'

      # environment - The name of the environment that was deployed to.
      # status - The status of the deployment, such as "success" or "failed".
      # version - The raw deployment version, as passed from the deployer.
      def initialize(environment, status, version)
        @environment = environment
        @status = status
        @version = version
      end

      def qa_commit_range
        unless @environment == STAGING && @status == 'success'
          return []
        end

        current, previous = GitlabClient
          .deployments(Project::GitlabEe, @environment)
          .first(2)
          .map(&:sha)

        [previous, current]
      end

      def track
        logger.info(
          'Recording GitLab deployment',
          environment: @environment,
          status: @status,
          version: @version
        )

        unless DEPLOYMENT_STATUSES.include?(@status)
          raise(
            ArgumentError,
            "The deployment status #{@status} is not supported"
          )
        end

        version = DeploymentVersionParser.new.parse(@version)
        omnibus_version = OmnibusDeploymentVersionParser.new.parse(@version)
        gitlab_deployment = track_gitlab_deployment(version)
        gitaly_deployment = track_gitaly_deployment(version.sha)
        omnibus_deployment = track_omnibus_deployment(omnibus_version)

        [gitlab_deployment, gitaly_deployment, omnibus_deployment].compact
      end

      private

      def track_gitlab_deployment(version)
        logger.info(
          'Recording GitLab Rails deployment',
          environment: @environment,
          status: @status,
          sha: version.sha,
          ref: version.ref
        )

        data = GitlabClient.create_deployment(
          Project::GitlabEe,
          @environment,
          version.ref,
          version.sha,
          @status,
          tag: version.tag?
        )

        Deployment.new(Project::GitlabEe, data.id, data.status)
      end

      def track_gitaly_deployment(gitlab_sha)
        version = ComponentVersions.get_component(
          gitlab_sha,
          Project::Gitaly.version_file
        )

        ref, sha, is_tag = gitaly_deployment_details(version)

        logger.info(
          'Recording Gitaly deployment',
          environment: @environment,
          status: @status,
          sha: sha,
          ref: ref
        )

        data = GitlabClient.create_deployment(
          Project::Gitaly,
          @environment,
          ref,
          sha,
          @status,
          tag: is_tag
        )

        Deployment.new(Project::Gitaly, data.id, data.status)
      end

      def gitaly_deployment_details(version)
        if version.match?(GITALY_TAGGED_RELEASE_REGEX)
          tag = GitlabClient.tag(Project::Gitaly, tag: "v#{version}")

          [tag.name, tag.commit.id, true]
        elsif version.match?(GITALY_SHA_REGEX)
          [GITALY_DEPLOY_REF, version, false]
        else
          raise "The Gitaly version #{sha} is not recognised"
        end
      end

      def track_omnibus_deployment(version)
        logger.info(
          'Recording Omnibus GitLab deployment',
          environment: @environment,
          status: @status,
          sha: version.sha,
          ref: version.ref
        )

        data = GitlabClient.create_deployment(
          Project::OmnibusGitlab,
          @environment,
          version.ref,
          version.sha,
          @status,
          tag: version.tag?
        )

        Deployment.new(Project::OmnibusGitlab, data.id, data.status)
      end
    end
  end
end
