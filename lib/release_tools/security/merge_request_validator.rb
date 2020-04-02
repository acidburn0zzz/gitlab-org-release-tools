# frozen_string_literal: true

module ReleaseTools
  module Security
    class MergeRequestValidator
      attr_reader :errors

      # A regular expression to use for extracting all pending tasks from the
      # merge request description. This pattern will match the following:
      #
      #     - [ ] Task name here
      #     * [ ] Task name here
      PENDING_TASKS = /(\*|-)\s*\[\s+\]/.freeze

      # A regular expression to use for extracting all tasks (pending or not)
      # from the merge request description. This pattern will match the
      # following:
      #
      #     - [ ] Task name here
      #     * [ ] Task name here
      #     - [x] Task name here
      #     * [x] Task name here
      ALL_TASKS = /(\*|-)\s*\[(\s+|[xX])\]/.freeze

      # A regular expression to use to determine if the merge request was
      # assigned to a reviewer.
      APPROVED_TASK = /(\*|-)\s*\[[xX]\]\s*Assign to a reviewer/.freeze

      # A regular expression used to determine if the target branch of a merge
      # request is valid.
      ALLOWED_TARGET_BRANCHES = /^(master|\d+-\d+-stable(-ee)?)$/.freeze

      # The label that must be applied to all security merge requests.
      SECURITY_LABEL = 'security'

      # The namespace that security implementation issues must reside in.
      SECURITY_NAMESPACE = 'gitlab-org/security'

      # @param [Gitlab::ObjectifiedHash] merge_request
      # @param [ReleaseTools::Security::Client] client
      def initialize(merge_request, client)
        @merge_request = merge_request
        @client = client
        @errors = []
      end

      def validate
        validate_pipeline_status
        validate_merge_status
        validate_work_in_progress
        validate_pending_tasks
        validate_milestone
        validate_merge_request_template
        validate_reviewed
        validate_target_branch
        validate_discussions
        validate_labels
        validate_closing_security_issue
      end

      def validate_pipeline_status
        pipeline = Pipeline.latest_for_merge_request(@merge_request, @client)

        if pipeline.nil?
          error('Missing pipeline', <<~ERROR)
            No pipeline could be found for this merge request. Security merge
            requests must have a pipeline that passes before they can be merged.
          ERROR
        elsif pipeline.failed?
          error('Failing pipeline', <<~ERROR)
            The latest pipeline has one or more failing builds. Merge requests
            can not be merged unless the pipeline has passed.
          ERROR
        elsif pipeline.pending?
          # This covers pipelines that are skipped, still running, or in another
          # unknown state.
          error('Pending pipeline', <<~ERROR)
            The latest pipeline did not pass, or is still running. Merge
            requests should not be assigned to me until the pipeline(s) have
            finished.
          ERROR
        end
      end

      def validate_merge_status
        if @merge_request.merge_status == 'cannot_be_merged'
          error('The merge request can not be merged', <<~ERROR)
            This merge request can currently not be merged, likely due to merge
            conflicts introduced by other (security) merge requests. Please
            rebase this merge request with the target branch and resolve any
            conflicts.
          ERROR
        end
      end

      def validate_work_in_progress
        if @merge_request.title.start_with?('WIP')
          error('The merge request is marked as a work in progress', <<~ERROR)
            Work in progress merge requests will not be merged, so make sure to
            resolve the WIP status before assigning this merge request back to
            me.
          ERROR
        end
      end

      def validate_pending_tasks
        if @merge_request.description.match?(PENDING_TASKS)
          error('There are one or more pending tasks', <<~ERROR)
            Before a security merge request can be merged, _all_ tasks must have
            been completed. If a task is not applicable, you can either mark it
            as completed or remove it.
          ERROR
        end
      end

      def validate_milestone
        if @merge_request.milestone.nil?
          error('The merge request does not have a milestone', <<~ERROR)
            This merge request does not appear to have a milestone. Backports
            must use the milestone of the version they target. Merge requests
            targeting master should use the latest milestone.
          ERROR
        end
      end

      def validate_merge_request_template
        unless @merge_request.description.match?(ALL_TASKS)
          error('The Security Release template is not used', <<~ERROR)
            This merge request does not contain any tasks to complete,
            suggesting that the "Security Release" merge request template was
            not used. Security merge requests must use this merge request
            template.
          ERROR
        end
      end

      def validate_reviewed
        unless @merge_request.description.match?(APPROVED_TASK)
          error('The merge request is not reviewed', <<~ERROR)
            This merge request appears to not have been reviewed. Make sure that
            the following task is present and completed:

                - [ ] Assign to a reviewer
          ERROR
        end
      end

      def validate_target_branch
        unless @merge_request.target_branch.match?(ALLOWED_TARGET_BRANCHES)
          error('The target branch is invalid', <<~ERROR)
            Security merge requests must target `master`, or a stable branch
            such as 11-8-stable (or 11-8-stable-ee for Enterprise Edition).

            Security branches are no longer in use and should not be used as
            target branches.
          ERROR
        end
      end

      def validate_discussions
        # There might be many discussions and notes. Buffering all of those in
        # an Array might require quite a bit of memory, so instead we process
        # discussions as we retrieve them.
        @client
          .merge_request_discussions(@merge_request.project_id, @merge_request.iid)
          .auto_paginate do |discussion|
            if discussion.notes.any? { |n| n['resolvable'] && !n['resolved'] }
              error('There are unresolved discussions', <<~ERROR)
                This merge request has one or more unresolved discussions,
                preventing it from being merged. Please mark all discussions as
                resolved, then assign this merge request back to me.
              ERROR

              break
            end
          end
      end

      def validate_labels
        unless @merge_request.labels.include?(SECURITY_LABEL)
          error(%{The merge request is missing the ~#{SECURITY_LABEL} label}, <<~ERROR)
            This merge request is missing the ~#{SECURITY_LABEL} label. This
            label is added automatically when using the security release merge
            request template. The lack of this label suggests the template may
            not have been used (correctly).

            Merge requests without this label will not be merged.
          ERROR
        end
      end

      # Validates if a merge request will automatically close the security
      # implementation issue when merged.
      #
      # Closing issues automatically only works if the merge request targets
      # the default project's branch, so we return early unless the merge request
      # targets master
      def validate_closing_security_issue
        return unless @merge_request.target_branch == 'master'

        issue_to_be_closed = @client
          .merge_request_closes_issues(@merge_request.project_id, @merge_request.iid)
          .detect { |issue| issue.web_url.match?(SECURITY_NAMESPACE) }

        return unless issue_to_be_closed.nil?

        error('The merge request must close the security implementation issue', <<~ERROR)
          This merge request is targeting master and it should close the security implementation
          issue when merged. Please add `Closes #<Security issue IID>` to the merge request
          description.
        ERROR
      end

      # @param [String] summary
      # @param [String] details
      def error(summary, details)
        @errors << <<~HTML
          <details>
          <summary><strong>#{summary}</strong></summary>
          <br />

          #{details}

          </details>
        HTML
      end
    end
  end
end
