# frozen_string_literal: true

module ReleaseTools
  module Services
    class AutoDeployBranchService
      include ::SemanticLogger::Loggable
      include BranchCreation

      CI_VAR_AUTO_DEPLOY = 'AUTO_DEPLOY_BRANCH'

      attr_reader :branch_name

      def initialize(branch_name)
        @branch_name = branch_name
      end

      def create_branches!
        # Find passing commits before creating branches
        ref_ee = latest_successful_ref(Project::GitlabEe)
        ref_omnibus = latest_successful_ref(Project::OmnibusGitlab)
        ref_cng = latest_successful_ref(Project::CNGImage)
        ref_helm = latest_successful_ref(Project::HelmGitlab)

        results = [
          create_branch_from_ref(Project::GitlabEe, branch_name, ref_ee),
          create_branch_from_ref(Project::OmnibusGitlab, branch_name, ref_omnibus),
          create_branch_from_ref(Project::CNGImage, branch_name, ref_cng),
          create_branch_from_ref(Project::HelmGitlab, branch_name, ref_helm)
        ]

        update_auto_deploy_ci

        results
      end

      private

      def version
        @version ||= gitlab_client.current_milestone.title.tr('.', '-')
      end

      def latest_successful_ref(project, client = gitlab_client)
        ReleaseTools::Commits.new(project, client: client).latest_successful.id
      end

      def update_auto_deploy_ci
        gitlab_client.update_variable(Project::ReleaseTools.path, CI_VAR_AUTO_DEPLOY, branch_name)
      rescue Gitlab::Error::NotFound
        gitlab_client.create_variable(Project::ReleaseTools.path, CI_VAR_AUTO_DEPLOY, branch_name)
      end
    end
  end
end
