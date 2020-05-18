# frozen_string_literal: true

module ReleaseTools
  module Security
    # Merging valid security merge requests in batches
    class MergeRequestsBatchMerger
      include ::SemanticLogger::Loggable

      ERROR_BATCH_TEMPLATE = <<~ERROR.strip
        @%<author_username>s

        Some of the merge requests associated with #%<security_issue_iid>s are not ready
        to be merged. Please review them, fix any problems reported and resolve all
        merge conflicts (in case there are any).

        Once resolved and the pipelines have passed, assign all merge
        requests back to me and mark this discussion as resolved.

        #{MergeRequestsValidator::ERROR_FOOTNOTE}
      ERROR

      # @param [ReleaseTools::Security::Client] client
      def initialize(client)
        @client = client
        @result = BatchMergerResult.new
      end

      # Merges valid security merge requests in batches:
      #
      # 1. Fetches security implementation issues associated to the last security release.
      # 2. Iterates over every security implementation issue and validates their
      # associated merge requests
      # 3. If one of the merge requests is invalid, it assignes them back to the author,
      # creates a discussion on the merge request targeting master and continues to the next
      # security implementation issue.
      # 4. If all of the merge requests are valid, merges them.
      def execute
        security_issues = prepare_security_issues

        return if security_issues.empty?

        security_issues.each do |security_issue|
          @result.processed << security_issue

          invalid_merge_requests = validated_merge_requests(security_issue.merge_requests).last

          if invalid_merge_requests.any?
            @result.invalid << security_issue

            reassign_merge_requests(security_issue)
          else
            merge_in_batches(security_issue)
          end
        end

        notify_result
      end

      private

      def prepare_security_issues
        security_issues = Security::IssuesValidator
          .new
          .execute
      end

      def security_issues
        @security_issues ||=
          Security::IssueCrawler
            .new
            .upcoming_security_issues_and_merge_requests
            .select(&:merge_requests_ready?)
      end

      def validated_merge_requests(merge_requests)
        MergeRequestsValidator
          .new(@client)
          .execute(merge_requests: merge_requests)
      end

      # Re-assigns merge requests back to the author.
      #
      # Then, notifies the author about the merge requests not
      # being valid by adding a discussion on the merge request
      # targeting master.
      def reassign_merge_requests(security_issue)
        logger.info("Merge requests of ##{security_issue.iid} are not valid. Re-assigning them back to the author.")

        mr_master = security_issue.merge_request_targeting_master

        return if SharedStatus.dry_run?

        @client.create_merge_request_discussion(
          mr_master.project_id,
          mr_master.iid,
          body: format(
            ERROR_BATCH_TEMPLATE,
            security_issue_iid: security_issue.iid,
            author_username: mr_master.author.username
          )
        )

        security_issue.merge_requests.each do |merge_request|
          @client.update_merge_request(
            merge_request.project_id,
            merge_request.iid,
            assignee_id: merge_request.author.id
          )
        end
      end

      # Merges merge requests in batches.
      #
      # First, merges the merge request targeting master, then the ones
      # targeting stable branches. If a merge request could not be
      # merged, it's logged and mark as pending.
      #
      # If all merge requests were merged, the one targeting master is
      # cherry-pick into the current auto deploy branch
      def merge_in_batches(security_issue)
        logger.info("Merging merge requests for: ##{security_issue.iid}")

        mr_targeting_master = security_issue.merge_request_targeting_master
        mrs_targeting_stable = security_issue.merge_requests_targeting_stable

        return if SharedStatus.dry_run?

        merge_merge_request(security_issue, mr_targeting_master)

        mrs_targeting_stable.each do |merge_request|
          merge_merge_request(security_issue, merge_request)
        end
      end

      def merge_merge_request(security_issue, merge_request)
        logger.trace(__method__, merge_request: merge_request.web_url)

        merged_result = @client.accept_merge_request(
          merge_request.project_id,
          merge_request.iid,
          squash: true
        )

        if merged_result.respond_to?(:merge_commit_sha) && merged_result.merge_commit_sha.present?
          logger.info("Merged security merge request", url: merge_request.web_url)

          cherry_pick_into_auto_deploy(merged_result) if merge_request.target_branch == 'master'
        else
          logger.fatal("Merge request #{merge_request.web_url} couldn't be merged")

          @result.pending[security_issue.iid] << merge_request
        end
      end

      def cherry_pick_into_auto_deploy(merge_request)
        ReleaseTools::Security::CherryPicker
          .new(@client, merge_request)
          .execute
      end

      def notify_result
        Slack::ChatopsNotification.security_issues_processed(@result)
      end
    end
  end
end
