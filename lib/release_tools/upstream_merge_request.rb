# frozen_string_literal: true

module ReleaseTools
  class UpstreamMergeRequest < MergeRequest
    CE_TO_EE_TEAM = %w[
      dzaporozhets
      vsizov
      rymai
      godfat
      winh
    ].freeze

    INCLUDED_CORE_MEMBERS = %w[
      blackst0ne
    ].freeze

    def self.project
      Project::GitlabEe
    end

    def self.labels
      'CE upstream'
    end

    def self.open_mrs
      GitlabClient
        .merge_requests(project, labels: labels, state: 'opened')
        .select { |mr| mr.target_branch == 'master' }
    end

    def project
      self.class.project
    end

    def labels
      self.class.labels
    end

    def title
      self[:title] ||= "CE upstream - #{Time.now.utc.strftime('%F %H:%M UTC')}"
    end

    def description
      return if conflicts.nil?

      if conflicts.empty?
        '**Congrats, no conflicts!** :tada:'
      else
        out = StringIO.new
        out.puts("Files to resolve:\n\n")
        conflicts.each do |conflict|
          username = authors[conflict[:path]]
          username = "`#{username}`" unless self[:mention_people]

          out.puts conflict_checklist_item(user: username, file: conflict[:path], conflict_type: conflict[:conflict_type])
        end
        out.puts
        out.puts <<~DESCRIPTION
          Try to resolve one file per commit, and then push (no force-push!) to the `#{source_branch}` branch.

          [More detailed instructions](https://docs.gitlab.com/ee/development/automatic_ce_ee_merge.html#what-to-do-if-you-are-pinged-in-a-ce-upstream-merge-request-to-resolve-a-conflict)

          Thanks in advance! :heart:

          #{responsible_gitlab_username} After you resolved the conflicts,
          please assign to the next person. If you're the last one to resolve
          the conflicts, please push this to be merged and **do not** choose to
          squash the commits.

          Note: This merge request was [created by an automated script](#{CI.current_job_url}).
          Please report any issue at https://gitlab.com/gitlab-org/release-tools/issues!

          /assign #{responsible_gitlab_username}
        DESCRIPTION
        out.string
      end
    end

    def source_branch
      self[:source_branch] || "ce-to-ee-#{Time.now.utc.to_date.iso8601}"
    end

    private

    def authors
      @authors ||= begin
        team = Team.new(included_core_members: INCLUDED_CORE_MEMBERS)

        conflicts.each_with_object({}) do |conflict, result|
          result[conflict[:path]] =
            CommitAuthor.new(conflict[:user], team: team).to_gitlab
        end
      end
    end

    def responsible_gitlab_username
      @responsible_gitlab_username ||=
        most_mentioned_gitlab_username ||
        "@#{CE_TO_EE_TEAM.sample}"
    end

    def most_mentioned_gitlab_username
      gitlab_users = authors.values.select { |name| name.start_with?('@') }

      sample_most_duplicated(gitlab_users)
    end

    def sample_most_duplicated(array)
      value_to_counts = array.group_by(&:itself).transform_values(&:size)
      count_to_values = value_to_counts.group_by(&:last)
      most_duplicated = count_to_values.sort_by(&:first).dig(-1, -1)

      most_duplicated&.sample&.first # count to values pair, first for value
    end

    def conflict_checklist_item(user:, file:, conflict_type:)
      "- [ ] #{user} Please resolve [(#{conflict_type}) `#{file}`](https://gitlab.com/#{project.path}/blob/#{source_branch}/#{file})"
    end
  end
end