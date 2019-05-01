# frozen_string_literal: true

module ReleaseTools
  # Represents an auto-deploy branch for purposes of cherry-picking
  class AutoDeployBranch
    attr_reader :version
    attr_reader :branch_name

    def initialize(version, branch_name)
      @version = version
      @branch_name = branch_name
    end

    def exists?
      true
    end

    # Included in cherry-pick summary messages
    def pick_destination
      "`#{branch_name}`"
    end

    def release_issue
      ReleaseTools::MonthlyIssue.new(version: version)
    end
  end
end