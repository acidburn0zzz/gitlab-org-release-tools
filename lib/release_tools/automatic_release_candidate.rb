# frozen_string_literal: true

module ReleaseTools
  # Preparing of automatic, periodic release candidates.
  #
  # This class can be used to automatically and periodically update stable
  # branches for an automatically tagged release candidate.
  class AutomaticReleaseCandidate
    include ::SemanticLogger::Loggable

    attr_reader :package_version, :gitlab_bot_client

    # The labels to apply to the merge request used for updating stable
    # branches.
    LABELS = %w[backstage team::Delivery].freeze

    # The project used for creating automatic RC merge requests.
    PROJECT = Project::GitlabEe

    # The datetime format to use for creating RC identifiers, such as
    # "20200305160438". This format is used to ensure that every automatic RC
    # uses a unique RC identifier.
    RC_FORMAT = '%Y%m%d%H%M%S'

    # The environment used for recording production deployments.
    PRODUCTION = 'gprd'

    def initialize(today = Time.now.utc)
      @release_version =
        ReleaseTools::ReleaseManagers::Schedule.new.version_for_date(today)

      unless @release_version
        raise "The release managers schedule for #{today} does not specify a milestone"
      end

      @package_version =
        "#{@release_version.to_minor}.0-rc#{today.strftime(RC_FORMAT)}.ee.0"

      @gitlab_bot_client = Gitlab::Client.new(
        endpoint: GitlabClient::DEFAULT_GITLAB_API_ENDPOINT,
        private_token: ENV.fetch('GITLAB_BOT_PRODUCTION_TOKEN')
      )
    end

    def prepare
      unless branch_exists?(target_branch)
        logger.info(
          "The target branch #{target_branch} does not exist, " \
            "so no merge request to update it is needed"
        )

        return package_version
      end

      return if SharedStatus.dry_run?

      create_source_branch

      # This produces comparison similar to using target...source, which ensures
      # we only get the commits added in the source branch but not yet present
      # in the target branch.
      new_commits = GitlabClient
        .client
        .compare(PROJECT, target_branch, source_branch)
        .commits

      if new_commits.empty?
        logger.info(
          "There is no difference between #{source_branch} and " \
            "#{target_branch}, so no merge request is needed"
        )

        delete_source_branch
      else
        update_target_branch
      end

      package_version
    end

    def update_target_branch
      logger.info(
        'Creating merge request to update the target branch',
        source_branch: source_branch,
        target_branch: target_branch
      )

      merge_request = GitlabClient.client.create_merge_request(
        GitlabClient.project_path(PROJECT),
        "Update stable branch #{target_branch} for automatic RC #{package_version}",
        description: merge_request_description,
        assignee_id: GitlabClient.current_user.id,
        labels: LABELS.join(','),
        source_branch: source_branch,
        target_branch: target_branch,
        remove_source_branch: true
      )

      logger
        .info('Accepting merge request', merge_request: merge_request.web_url)

      # When the MR is created a new pipeline is started. Waiting for these
      # pipelines to complete can take a while, and serves no benefit for
      # creating RCs.
      GitlabClient
        .client
        .merge_request_pipelines(merge_request.project_id, merge_request.iid)
        .auto_paginate do |p|
          next unless p.status == 'running' || p.status == 'created'

          GitlabClient.client.cancel_pipeline(merge_request.project_id, p.id)
        end

      # Approving the merge request can't be done by the author, so for
      # approving and merging we use gitlab-bot instead of the release-tools
      # bot.
      gitlab_bot_client
        .approve_merge_request(merge_request.project_id, merge_request.iid)

      # Sometimes accepting a merge request does not result in the source branch
      # being removed immediately, despite this option being set when creating
      # the merge request. To ensure the branch is really removed, we once again
      # tell the API to remove the source branch when merging the merge request.
      gitlab_bot_client.accept_merge_request(
        merge_request.project_id,
        merge_request.iid,
        should_remove_source_branch: true
      )
    end

    def branch_exists?(name)
      GitlabClient.find_branch(name, PROJECT).present?
    end

    def create_source_branch
      deploy = GitlabClient.deployments(PROJECT, PRODUCTION).first

      unless deploy
        raise "There are no deployments to use for updating the stable branch"
      end

      # Each deployment creates a ref that points to the deployed commit. We
      # can use this ref to create a source branch for our merge request. This
      # ensures that we only merge changes actually deployed into our stable
      # branch.
      GitlabClient.create_branch(
        source_branch,
        "refs/environments/#{PRODUCTION}/deployments/#{deploy.iid}",
        PROJECT
      )
    end

    def delete_source_branch
      GitlabClient.delete_branch(source_branch, PROJECT)
    end

    def merge_request_description
      <<~MESSAGE
        This updates the stable branch #{target_branch} for the automatically
        tagged RC #{package_version}. The RC will be tagged automatically when
        this merge request is merged.

        :robot: This merge request is generated automatically using the [Release
        Tools](https://gitlab.com/gitlab-org/release-tools/) project.

        /milestone %#{@release_version.milestone_name}
      MESSAGE
    end

    def source_branch
      "release-tools/#{@package_version}"
    end

    def target_branch
      @release_version.stable_branch(ee: true)
    end
  end
end
