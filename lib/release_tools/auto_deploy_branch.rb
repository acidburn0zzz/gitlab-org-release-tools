# frozen_string_literal: true

module ReleaseTools
  # Represents an auto-deploy branch for purposes of cherry-picking
  class AutoDeployBranch
    attr_reader :version
    attr_reader :branch_name

    # Return the current auto-deploy branch name from environment variable
    def self.current_name
      ENV.fetch('AUTO_DEPLOY_BRANCH')
    end

    def self.current
      new(current_name)
    end

    def initialize(name)
      major, minor = name.split('-', 3).take(2)

      @version = Version.new("#{major}.#{minor}")
      @branch_name = name
      @time = Time.now.utc
    end

    def exists?
      true
    end

    def to_s
      branch_name
    end

    # Included in cherry-pick summary messages
    def pick_destination
      "`#{branch_name}`"
    end

    def release_issue
      ReleaseTools::MonthlyIssue.new(version: version)
    end

    # Returns a timestamp to use for auto-deploy tag names. This is decoupled
    # from any branch creation times so that we can use the same timestamp for
    # all packagers (CNG, Omnibus, etc).
    def tag_timestamp
      @time.strftime('%Y%m%d%H%M')
    end
  end
end
