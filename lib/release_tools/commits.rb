# frozen_string_literal: true

module ReleaseTools
  class Commits
    include ::SemanticLogger::Loggable

    MAX_COMMITS_TO_CHECK = 100

    def initialize(project, ref: 'master', client: ReleaseTools::GitlabClient)
      @project = project
      @ref = ref
      @client = client
    end

    # Get the latest commit for `ref`
    def latest
      commit_list.first
    end

    # Get the latest commit for `ref` with a successful pipeline
    def latest_successful
      commit_list.detect(&method(:success?))
    end

    # Get the latest commit for `ref` with a succesful pipeline run that's been
    # mirrored to Build
    def latest_successful_on_build
      commit_list.detect do |commit|
        next unless success?(commit)

        begin
          # Hit the dev API with the specified commit to see if it even exists
          ReleaseTools::GitlabDevClient.commit(@project.dev_path, ref: commit.id)

          logger.info(
            'Passing commit found on Build',
            project: @project.dev_path,
            commit: commit.id
          )
        rescue Gitlab::Error::Error
          logger.debug(
            'Commit passed on Canonical, missing on Build',
            project: @project.dev_path,
            commit: commit.id
          )

          false
        end
      end
    end

    private

    def commit_list
      # NOTE: We always gather commits from the Security mirror, since it
      # receives both regular and security changes.
      @commit_list ||= @client.commits(
        @project.security_path,
        per_page: MAX_COMMITS_TO_CHECK,
        ref_name: @ref
      )
    end

    def success?(commit)
      result = @client.commit(@project.security_path, ref: commit.id)

      return false if result.status != 'success'
      return true if @project != ReleaseTools::Project::GitlabEe

      # Prevent false positive on docs-only pipelines
      #
      # A gitlab full pipeline has over 200 jobs, but isn't necessarily consistent
      # about the order, so we're only checking size
      @client
        .pipeline_jobs(@project.security_path, result.last_pipeline.id, per_page: 50)
        .has_next_page?
    end
  end
end
