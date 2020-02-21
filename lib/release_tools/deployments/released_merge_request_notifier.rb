# frozen_string_literal: true

module ReleaseTools
  module Deployments
    # Notifying of deployed merge requests that they will be included in the
    # next release.
    module ReleasedMergeRequestNotifier
      TEMPLATE = <<~COMMENT
        This merge request has been deployed to the pre.gitlab.com environment,
        and will be included in the upcoming [self-managed GitLab][self-managed]
        %<version>s release.

        <hr/>

        :robot: This comment is generated automatically using the
        [Release Tools][release-tools] project.

        /label ~published

        [self-managed]: https://about.gitlab.com/handbook/engineering/releases/#self-managed-releases-1
        [release-tools]: https://gitlab.com/gitlab-org/release-tools/
      COMMENT

      # The environment packages ready for release are deployed to.
      RELEASE_ENVIRONMENT = 'pre'

      # environment - The name of the environment that was deployed to.
      # deployments - An Array of `DeploymentTrackes::Deployment` instances,
      #               containing data about a deployment.
      # version - a String containing the version that was deployed.
      def self.notify(environment, deployments, version)
        unless environment == RELEASE_ENVIRONMENT
          ReleaseTools.logger.info(
            'Not notifying released merge requests for this environment',
            environment: environment
          )

          return
        end

        parsed_version = Version.new(version)

        # If the version format is something we don't recognise (e.g. we deploy
        # an auto deploy package to pre for some reason), we don't want to
        # notify merge requests about the deployment.
        unless parsed_version.valid?
          ReleaseTools.logger.warn(
            'Not notifying released merge requests since the version is not supported',
            environment: environment,
            version: version
          )

          return
        end

        ReleaseTools.logger.info(
          'Notifying merge requests that will be released',
          environment: environment,
          version: version
        )

        comment = format(TEMPLATE, version: parsed_version.to_patch)

        MergeRequestUpdater
          .for_successful_deployments(deployments)
          .add_comment(comment)
      end
    end
  end
end
