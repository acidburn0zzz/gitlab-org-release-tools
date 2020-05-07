# frozen_string_literal: true

module ReleaseTools
  module Security
    # Cherry-pick security merge requests from `master` into the current
    # auto-deploy branch.
    class CherryPicker
      include ::SemanticLogger::Loggable

      def initialize(client, merge_request)
        @client = client
        @merge_request = merge_request
        @target = ReleaseTools::AutoDeployBranch.current_name
      end

      def execute
        return unless Feature.enabled?(:security_cherry_picker)

        if @merge_request.merge_commit_sha.present?
          cherry_pick_into_auto_deploy
        else
          logger.fatal(
            'Security merge request does not have a merge commit sha',
            merge_request: @merge_request.web_url,
            target: @target
          )
        end
      end

      private

      def cherry_pick_into_auto_deploy
        @client.cherry_pick_commit(
          @merge_request.project_id,
          @merge_request.merge_commit_sha,
          @target
        )

        logger.info(
          'Cherry-picked security merge request to auto-deploy',
          project: @merge_request.project_id,
          ref: @merge_request.merge_commit_sha,
          target: @target,
          merge_request: @merge_request.web_url
        )
      rescue ::Gitlab::Error::Error => ex
        logger.fatal(
          'Failed security cherry-pick to auto-deploy',
          project: @merge_request.project_id,
          ref: @merge_request.merge_commit_sha,
          target: @target,
          merge_request: @merge_request.web_url,
          error: ex.message
        )
      end
    end
  end
end
