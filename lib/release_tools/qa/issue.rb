# frozen_string_literal: true

module ReleaseTools
  module Qa
    class Issue < ReleaseTools::Issue
      def title
        "#{version} QA Issue"
      end

      def labels
        'QA task'
      end

      def add_comment(message)
        ReleaseTools::GitlabClient
          .create_issue_note(project, issue: remote_issuable, body: message)
      end

      def link!
        parent = parent_issue

        ReleaseTools::GitlabClient.link_issues(self, parent) if parent.exists?
      end

      def create?
        merge_requests.any?
      end

      def gitlab_test_instance
        # Patch releases are deployed to preprod
        # Auto-deploy releases are deployed to staging
        auto_deploy_version? ? 'https://staging.gitlab.com' : 'https://pre.gitlab.com'
      end

      def parent_issue
        # For auto-deploy QA issues we can't use the raw version, as there is no
        # monthly release issue for auto-deploy versions. To handle this we
        # always convert the input version to a MAJOR.MINOR version.
        ReleaseTools::PatchIssue.new(version: Version.new(version.to_minor))
      end

      protected

      def template_path
        File.expand_path('../../../templates/qa.md.erb', __dir__)
      end

      def issue_presenter
        ReleaseTools::Qa::IssuePresenter
          .new(merge_requests, self, version)
      end

      def auto_deploy_version?
        version =~ ReleaseTools::Qa::Ref::AUTO_DEPLOY_TAG_REGEX
      end
    end
  end
end
