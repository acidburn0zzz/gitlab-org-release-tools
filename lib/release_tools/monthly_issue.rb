# frozen_string_literal: true

module ReleaseTools
  class MonthlyIssue < Issue
    def title
      "Release #{version.to_minor}"
    end

    def labels
      'Monthly Release,team::Delivery'
    end

    def project
      ::ReleaseTools::Project::Release::Tasks
    end

    def assignees
      ReleaseManagers::Schedule.new.ids_for_version(version)
    rescue ReleaseManagers::Schedule::VersionNotFoundError
      nil
    end

    protected

    def template_path
      File.expand_path('../../templates/monthly.md.erb', __dir__)
    end
  end
end
