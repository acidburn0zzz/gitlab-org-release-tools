# frozen_string_literal: true

module ReleaseTools
  class PassingBuild
    include ::SemanticLogger::Loggable

    attr_reader :ref

    def initialize(ref)
      @project = ReleaseTools::Project::GitlabEe
      @ref = ref
    end

    def execute(trigger: false)
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

      @omnibus_version_map = ReleaseTools::ComponentVersions.get_omnibus_compat_versions(commit.id)
      @cng_version_map = ReleaseTools::ComponentVersions.get_cng_compat_versions(commit.id)

      trigger_build if trigger
    end

    def trigger_build
      if ref.match?(/\A(?:security\/)?\d+-\d+-auto-deploy-\d+\z/)
        auto_deploy_omnibus
        auto_deploy_cng
      else
        logger.fatal('Invalid ref for passing build trigger', ref: ref)
      end
    end

    def auto_deploy_omnibus
      ReleaseTools::ComponentVersions
        .update_omnibus(ref, @omnibus_version_map)

      ReleaseTools::AutoDeploy::Tagger::Omnibus
        .new(ref, @omnibus_version_map)
        .tag!
    end

    def auto_deploy_cng
      ReleaseTools::ComponentVersions
        .update_cng(ref, @cng_version_map)

      ReleaseTools::AutoDeploy::Tagger::CNGImage
        .new(ref, @cng_version_map)
        .tag!
    end
  end
end
