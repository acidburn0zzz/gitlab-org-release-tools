# frozen_string_literal: true

module ReleaseTools
  module Security
    # Validating of multiple security merge requests across different projects.
    class MergeRequestsValidator
      include ::SemanticLogger::Loggable

      PROJECTS_TO_VERIFY = %w[
        gitlab-org/security/gitlab
        gitlab-org/security/omnibus-gitlab
      ].freeze

      ERROR_FOOTNOTE = <<~FOOTNOTE.strip
        <hr>

        <sub>
          :robot: This is an automated message generated using the
          [release tools project](https://gitlab.com/gitlab-org/release-tools/).
          If you believe there is an error, please create an issue in the
          release tools project.
        </sub>
      FOOTNOTE

      ERROR_TEMPLATE = <<~TEMPLATE.strip
        @%<author_username>s

        This security merge request does not meet our requirements for
        security merge requests. Please take the following steps to ensure
        this merge request can be merged:

        1. Resolve all the errors listed below
        2. Mark this discussion as resolved
        3. Assign the merge request back to @%<bot_username>s

        ## Errors

        The following errors were detected:

        %<errors>s

        #{ERROR_FOOTNOTE}
      TEMPLATE

      # @param [ReleaseTools::Security::Client|ReleaseTools::Security::DevClient] client
      def initialize(client)
        @client = client
      end

      # Validates all security merge requests, returning those that were valid.
      #
      # The valid and invalid merge requests are returned so that other code can
      # use these MRs, for example by merging them.
      #
      # The return value is an Array of Arrays, in the following format:
      #
      #     [
      #       [valid_merge_request1, valid_merge_request2, ...],
      #       [invalid_merge_request1, invalid_merge_request2, ...]
      #     ]
      def execute
        valid = []
        invalid = []

        PROJECTS_TO_VERIFY.each do |project|
          logger.info('Verifying security MRs', project: project)

          merge_requests = @client.open_security_merge_requests(project)

          validated = Parallel
            .map(merge_requests, in_threads: Etc.nprocessors) do |mr|
              verify_merge_request(mr)
            end

          validated.each do |(is_valid, mr)|
            if is_valid
              valid << mr
            else
              invalid << mr
            end
          end
        end

        [valid, invalid]
      end

      # @param [Gitlab::ObjectifiedHash] basic_mr
      def verify_merge_request(basic_mr)
        logger.trace(__method__, merge_request: basic_mr.web_url)

        # Merge requests retrieved using the MR list API do not include all data
        # we need, such as pipeline details. To work around this we must perform
        # an additional request for every merge request to get this data.
        mr = @client.merge_request(basic_mr.project_id, basic_mr.iid)
        validator = MergeRequestValidator.new(mr, @client)

        validator.validate

        if validator.errors.any?
          reassign_with_errors(mr, validator.errors)

          [false, mr]
        else
          [true, mr]
        end
      end

      # @param [Gitlab::ObjectifiedHash] mr
      # @param [Array<String>] errors
      def reassign_with_errors(mr, errors)
        logger.trace(__method__, merge_request: mr.web_url, errors: errors.count)

        return if SharedStatus.dry_run?

        project_id = mr.project_id
        iid = mr.iid

        @client.create_merge_request_discussion(
          project_id,
          iid,
          body: format(
            ERROR_TEMPLATE,
            author_username: mr.author.username,
            bot_username: Client::RELEASE_TOOLS_BOT_USERNAME,
            errors: errors.join("\n\n")
          )
        )

        @client.update_merge_request(project_id, iid, assignee_id: mr.author.id)
      end
    end
  end
end
