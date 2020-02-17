# frozen_string_literal: true

module ReleaseTools
  module Deployments
    # Parallel updating of deployed merge requests.
    #
    # This class can be used to update deployed merge requests in parallel, such
    # as by adding a merge request comment and/or adding labels.
    class MergeRequestUpdater
      include ::SemanticLogger::Loggable

      # The base interval for retrying operations that failed, in seconds.
      RETRY_INTERVAL = 5

      # Returns a MergeRequestUpdater operating on successful deployments.
      def self.for_successful_deployments(deployments)
        new(deployments.select(&:success?))
      end

      # deployments - An Array of DeploymentTracker::Deployment instances.
      def initialize(deployments)
        @deployments = deployments
      end

      # Adds the comment to all deployed merge requests.
      #
      # comment - The comment to add, as a String.
      def add_comment(comment)
        each_merge_request do |mr|
          with_retries do
            logger.info("Adding comment to merge request #{mr.web_url}")

            GitlabClient
              .create_merge_request_comment(mr.project_id, mr.iid, comment)
          end
        end
      end

      # Adds the label to all merge requests.
      #
      # This does not use slash commands, as comments that _only_ include slash
      # commands are rejected by our API.
      def add_label(label)
        each_merge_request do |mr|
          with_retries do
            logger.info(
              "Adding label #{label.inspect} to merge request #{mr.web_url}"
            )

            GitlabClient.update_merge_request(
              mr.project_id,
              mr.iid,
              labels: [label, *mr.labels].join(',')
            )
          end
        end
      end

      private

      def each_merge_request(&block)
        @deployments.each do |deploy|
          each_deployment_merge_request(deploy.project, deploy.id, &block)
        end
      end

      def each_deployment_merge_request(project, deployment_id, &block)
        page = with_retries do
          GitlabClient.deployed_merge_requests(project, deployment_id)
        end

        while page
          Parallel.each(page.each.to_a, in_threads: Etc.nprocessors, &block)

          with_retries do
            page = page.next_page
          end
        end
      end

      def with_retries(&block)
        Retriable.retriable(base_interval: RETRY_INTERVAL, &block)
      end
    end
  end
end
