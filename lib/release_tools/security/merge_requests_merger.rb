# frozen_string_literal: true

module ReleaseTools
  module Security
    # Merging of valid security merge requests across different projects.
    class MergeRequestsMerger
      include ::SemanticLogger::Loggable

      attr_reader :client

      ERROR_TEMPLATE = <<~ERROR.strip
        @%<author_username>s

        This merge request could not be merged automatically. Please rebase this
        merge request with the target branch and resolve any conflicts that may
        appear. Once resolved and the pipelines have passed, assign this merge
        request back to me and mark this discussion as resolved.

        #{MergeRequestsValidator::ERROR_FOOTNOTE}
      ERROR

      # @param [ReleaseTools::Security::Client|ReleaseTools::Security::DevClient] client
      # @param [TrueClass|FalseClass] merge_master If merge requests that target
      # `master` should also be merged.
      def initialize(client, merge_master: false)
        @merge_master = merge_master
        @client = client
      end

      # Merges all valid security merge requests.
      # We group MRs by target branch so we don't attempt to merge multiple
      # MRs into the same target branch at the same time. This should lead to
      # better concurrency, as we have to spend less time waiting for previous
      # MRs to finish merging.
      #
      # It should also result in merges not happening less often, as we only
      # merge a new MR into the target branch when the previous one finishes
      # merging.
      #
      # If 'merge_in_batches' feature is enabled, calls MergeRequestsBatchMerger
      def execute
        if Feature.enabled?(:security_merge_in_batches)
          ReleaseTools::Security::MergeRequestsBatchMerger
            .new(client)
            .execute
        else
          validate_and_merge_by_projects
        end
      end

      def validate_and_merge_by_projects
        valid, invalid = validated_merge_requests
        to_merge = valid.group_by(&:target_branch)

        tuples = Parallel.map(to_merge, in_threads: Etc.nprocessors) do |_, mrs|
          mrs.map { |mr| merge(mr) }
        end

        return if SharedStatus.dry_run?

        merge_result = MergeResult
          .from_array(valid: tuples.flatten(1), invalid: invalid)

        Slack::ChatopsNotification.merged_security_merge_requests(merge_result)

        CherryPicker.new(client, merge_result.merged).execute if @merge_master

        merge_result
      end

      def validated_merge_requests
        valid, invalid = MergeRequestsValidator.new(@client).execute

        if @merge_master
          [valid, invalid]
        else
          [
            valid.reject { |mr| mr.target_branch == 'master' },
            invalid
          ]
        end
      end

      # @param [Gitlab::ObjectifiedHash] mr
      def merge(mr)
        logger.trace(__method__, merge_request: mr.web_url)

        return if SharedStatus.dry_run?

        merged_mr = client.accept_merge_request(
          mr.project_id,
          mr.iid,
          squash: true
        )

        if merged_mr.respond_to?(:merge_commit_sha) && merged_mr.merge_commit_sha
          [true, merged_mr]
        else
          reassign_merge_request(mr)

          [false, mr]
        end
      end

      # @param [Gitlab::ObjectifiedHash] mr
      def reassign_merge_request(mr)
        client.create_merge_request_discussion(
          mr.project_id,
          mr.iid,
          body: format(ERROR_TEMPLATE, author_username: mr.author.username)
        )

        client.update_merge_request(
          mr.project_id,
          mr.iid,
          assignee_id: mr.author.id
        )
      end
    end
  end
end
