# frozen_string_literal: true

module ReleaseTools
  class Commits
    include ::SemanticLogger::Loggable

    MAX_COMMITS_TO_CHECK = 100

    attr_reader :project

    def initialize(project, ref: 'master', client: ReleaseTools::GitlabClient)
      @project = project
      @ref = ref

      @client =
        if SharedStatus.security_release?
          # For security releases, we only work on dev
          ReleaseTools::GitlabDevClient
        else
          client
        end
    end

    def merge_base(other_ref)
      return unless Feature.enabled?(:merge_base_limit)

      @client.merge_base(project, [@ref, other_ref])&.id
    end

    # Get the latest commit for `ref`
    def latest
      commit_list.first
    end

    def latest_successful
      commit_list.detect(&method(:success?))
    end

    # Find a commit with a passing build on production that also exists on dev
    def latest_successful_on_build(limit: nil)
      commit_list.detect do |commit|
        if Feature.enabled?(:merge_base_limit) && commit.id == limit
          logger.info(
            'Reached the limit commit without a successful build',
            project: project,
            limit: limit
          )
          return nil
        end

        next unless success?(commit)

        begin
          # Hit the dev API with the specified commit to see if it even exists
          ReleaseTools::GitlabDevClient.commit(project, ref: commit.id)

          logger.info(
            'Passing commit found on Build',
            project: project,
            commit: commit.id
          )
        rescue Gitlab::Error::Error
          logger.debug(
            'Commit passed on Canonical, missing on Build',
            project: project,
            commit: commit.id
          )

          false
        end
      end
    end

    private

    def commit_list
      @commit_list ||= @client.commits(
        @project,
        per_page: MAX_COMMITS_TO_CHECK,
        ref_name: @ref
      )
    end

    def success?(commit)
      result = @client.commit(@project, ref: commit.id)

      if result.status != 'success'
        logger.info(
          'Skipping commit because the pipeline did not succeed',
          commit: commit.id,
          status: result.status
        )

        return false
      end

      return true if @project != ReleaseTools::Project::GitlabEe

      # Documentation-only changes result in a pipeline with only a few jobs.
      # If we were to include a passing documentation pipeline/commit, we may
      # end up also including code that broke a previous full pipeline.
      #
      # We also take into account QA only pipelines. These pipelines _should_ be
      # considered, but don't have a regular full pipeline. The "setup-test-env"
      # job is present for both regular and QA pipelines, but not for
      # documentation pipelines; hence we check for the presence of this job.
      # This is more reliable than just checking the amount of jobs.
      @client
        .pipeline_jobs(@project, result.last_pipeline.id)
        .auto_paginate do |job|
          return true if job.name.start_with?('setup-test-env')
        end

      logger.info(
        'Skipping commit because we could not find a full successful pipeline',
        commit: commit.id
      )

      false
    end
  end
end
