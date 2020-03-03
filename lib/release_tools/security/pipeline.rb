# frozen_string_literal: true

module ReleaseTools
  module Security
    class Pipeline
      FINISHED_STATES = %w[success failed].to_set

      # @param [Gitlab::ObjectifiedHash] merge_request
      # @param [ReleaseTools::Security::Client] client
      def self.latest_for_merge_request(merge_request, client)
        raw_pipeline =
          if merge_request.pipeline
            merge_request.pipeline
          else
            # For reasons unknown, the API doesn't always include a pipeline in
            # the merge request details. To work around this, we request the
            # latest pipeline for the current MR from the API.
            client.latest_merge_request_pipeline(
              merge_request.project_id,
              merge_request.iid
            )
          end

        new(client, merge_request.project_id, raw_pipeline) if raw_pipeline
      end

      # @param [ReleaseTools::Security::Client] client
      # @param [Integer] project_id
      # @param [Gitlab::ObjectifiedHash] raw_pipeline
      def initialize(client, project_id, raw_pipeline)
        @client = client
        @project_id = project_id
        @raw_pipeline = raw_pipeline
      end

      def passed?
        @raw_pipeline.status == 'success'
      end

      def pending?
        !FINISHED_STATES.include?(@raw_pipeline.status)
      end

      def failed?
        return false unless @raw_pipeline.status == 'failed'

        allowed_to_fail = allowed_failures

        latest_jobs.any? do |job|
          job.status == 'failed' && !allowed_to_fail.include?(job.name)
        end
      end

      def allowed_failures
        # When retrieving pipeline details the "allow_failure" field is not
        # included, only when retrieving commit statuses is it included. This
        # means we need to perform an additional API call to determine which
        # builds are allowed to fail.
        @client
          .commit_status(@project_id, @raw_pipeline.sha, per_page: 100)
          .auto_paginate
          .select(&:allow_failure)
          .map(&:name)
          .to_set
      end

      def latest_jobs
        # When requesting failed jobs, the API also includes jobs that were
        # later retried and passed. This means we need to manually determine
        # what jobs are the latest ones, then manually verify their statuses.
        latest_per_name = @client
          .pipeline_jobs(
            @project_id,
            @raw_pipeline.id,
            per_page: 100
          )
          .auto_paginate
          .each_with_object({}) do |job, hash|
            latest = hash[job.name]

            hash[job.name] = job if latest.nil? || latest.id < job.id
          end

        latest_per_name.values
      end
    end
  end
end
