# frozen_string_literal: true

module ReleaseTools
  class PreparationMergeRequest < MergeRequest
    include ::SemanticLogger::Loggable

    def title
      "WIP: Prepare #{version} release"
    end

    def labels
      'team::Delivery'
    end

    def source_branch
      branch_name
    end

    def target_branch
      stable_branch
    end

    def release_issue_url
      @release_issue_url ||= release_issue.url
    end

    def stable_branch
      version.stable_branch
    end

    def milestone
      version.milestone_name
    end

    def patch_or_rc_version
      if version.rc?
        "RC#{version.rc}"
      else
        version.to_s
      end
    end

    def branch_name
      if version.rc?
        "#{version.stable_branch}-prepare-rc#{version.rc}"
      else
        "#{version.stable_branch}-patch-#{version.patch}"
      end
    end

    def pick_destination
      url
    end

    def ee?
      version.ee?
    end

    def create_branch!
      Branch.new(name: source_branch, project: project).tap do |branch|
        unless SharedStatus.dry_run?
          logger.info(
            'Creating preparation branch',
            name: source_branch,
            target: stable_branch,
            project: project
          )

          branch.create(ref: target_branch)
        end
      end
    rescue Gitlab::Error::BadRequest => ex # 400 Branch already exists
      logger.warn(
        'Failed to create preparation branch',
        name: source_branch,
        target: target_branch,
        project: project,
        error_code: ex.response_status,
        error_message: ex.message
      )

      nil
    end

    def release_issue
      @release_issue ||=
        if version.monthly?
          MonthlyIssue.new(version: version)
        else
          PatchIssue.new(version: version)
        end
    end

    protected

    def template_path
      File.expand_path('../../templates/preparation_merge_request.md.erb', __dir__)
    end
  end
end
