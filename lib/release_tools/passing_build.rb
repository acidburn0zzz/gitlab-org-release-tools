# frozen_string_literal: true

module ReleaseTools
  class PassingBuild
    include ::SemanticLogger::Loggable

    attr_reader :ref

    def initialize(ref)
      @project = ReleaseTools::Project::GitlabEe
      @ref = ref
    end

    def execute
      commits = ReleaseTools::Commits.new(@project, ref: ref)

      commit =
        if SharedStatus.security_release?
          # Passing builds on dev are few and far between; for a security
          # release we'll just use the latest commit on the branch
          commits.latest
        else
          commits.latest_successful_on_build
        end

      if commit.nil?
        raise "Unable to find a passing #{@project} build for `#{ref}` on dev"
      end

      commit
    end

    private

    def wait_on_build(input)
      Parallel.each(input, in_threads: Etc.nprocessors) do |project, tag|
        ReleaseTools::Pipeline.new(project, tag).find_and_wait
      end
    end
  end
end
