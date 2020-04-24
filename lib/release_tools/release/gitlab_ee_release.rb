# frozen_string_literal: true

module ReleaseTools
  module Release
    class GitlabEeRelease < GitlabCeRelease
      private

      def project
        Project::GitlabEe
      end

      def release_name
        'gitlab-ee'
      end

      def after_execute_hook
        super

        # UBI-based CNG image release
        begin
          Release::CNGImageRelease
            .new(version, options.merge(gitlab_repo_path: repository.path, ubi: true))
            .execute
        rescue StandardError => ex
          logger.fatal('UBI-based CNG image release failed', error: ex.message)
        end
      end
    end
  end
end
