# frozen_string_literal: true

module ReleaseTools
  module Security
    # Crawling of security release issues to determine their associated security
    # issues and merge requests.
    class IssueCrawler
      # The public project that is used for creating the security root issues.
      PUBLIC_PROJECT = 'gitlab-org/gitlab'

      # The namespace that security issues must reside in.
      SECURITY_NAMESPACE = 'gitlab-org/security'

      # The label required by security root/meta issues.
      ROOT_ISSUE_LABEL = 'upcoming security release'

      # The label required for a related issue or merge request to be considered
      # by the crawler.
      SECURITY_LABEL = 'security'

      # The date format used by issue due dates.
      DUE_DATE_FORMAT = '%Y-%m-%d'

      # The status of issues and merge requests to be considered
      OPENED = 'opened'

      # A security issue and its merge requests.
      SecurityIssue = Struct.new(:project_id, :iid, :merge_requests)

      # Returns all the upcoming security release issues, sorted by their due
      # dates.
      def security_release_issues
        issues = GitlabClient
          .issues(PUBLIC_PROJECT, labels: ROOT_ISSUE_LABEL, state: OPENED)
          .auto_paginate

        # Ignoring issues without a due date could lead to security releases
        # being overlooked, so instead we error if we find an issue without a
        # due date.
        issues.each do |issue|
          next if issue.due_date

          raise "The issue #{issue.web_url} does not have a due date set"
        end

        issues.sort do |a, b|
          Date.strptime(a.due_date, DUE_DATE_FORMAT) <=>
            Date.strptime(b.due_date, DUE_DATE_FORMAT)
        end
      end

      # Returns all security issues for the upcoming security release.
      def upcoming_security_issues_and_merge_requests
        if (release_issue = security_release_issues[0])
          security_issues_and_merge_requests_for(release_issue.iid)
        else
          []
        end
      end

      # Returns all security issues and merge requests for the given root
      # security issue.
      #
      # The `release_issue_iid` is the IID of the (confidential) security issue
      # opened in the gitlab-org/gitlab project.
      def security_issues_and_merge_requests_for(release_issue_iid)
        related_issues = []

        GitlabClient
          .client
          .issue_links(PUBLIC_PROJECT, release_issue_iid)
          .auto_paginate do |issue|
            # The list of related issues may contain issues unrelated to
            # security merge requests. Since the issue links API does not have
            # any filtering capabilities, we must filter our unrelated issues
            # manually.
            next unless issue.labels.include?(SECURITY_LABEL)
            next unless issue.web_url.include?(SECURITY_NAMESPACE)

            related_issues << issue
          end

        Parallel.map(related_issues, in_threads: Etc.nprocessors) do |issue|
          mrs = []

          GitlabClient
            .related_merge_requests(issue.project_id, issue.iid)
            .auto_paginate do |mr|
              next unless mr.labels.include?(SECURITY_LABEL)
              next unless mr.web_url.include?(SECURITY_NAMESPACE)
              next unless mr.state == OPENED

              mrs << mr
            end

          SecurityIssue.new(issue.project_id, issue.iid, mrs)
        end
      end
    end
  end
end
