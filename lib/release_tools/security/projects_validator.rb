# frozen_string_literal: true

module ReleaseTools
  module Security
    # Validating merge requests on security projects
    class ProjectsValidator
      include ::SemanticLogger::Loggable

      PROJECTS_TO_VERIFY = %w[
        gitlab-org/security/gitlab
        gitlab-org/security/omnibus-gitlab
        gitlab-org/security/gitlab-pages
      ].freeze

      def initialize(client)
        @client = client
      end

      def execute
        PROJECTS_TO_VERIFY.each do |project|
          logger.info('Verifying security MRs', project: project)

          merge_requests = @client.open_security_merge_requests(project)

          validate_merge_requests(merge_requests)
        end
      end

      private

      def validate_merge_requests(merge_requests)
        MergeRequestsValidator
          .new(@client)
          .execute(merge_requests: merge_requests)
      end
    end
  end
end
