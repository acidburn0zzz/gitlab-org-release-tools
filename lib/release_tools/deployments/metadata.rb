# frozen_string_literal: true

module ReleaseTools
  module Deployments
    # Metadata about a deployment/release, such as the deployed component
    # versions and if a deployment/release is a security release.
    class Metadata
      # The `version` argument is the version of the package that was deployed,
      # such as `12.9.202003031051-77c80950e05.5f62a0bc739`.
      def initialize(version)
        @version = version
      end

      # Returns `true` if the release is a security release.
      def security_release?
        matches = @version.match(Qa::Ref::AUTO_DEPLOY_TAG_REGEX)

        if matches && matches[:omnibus_commit]
          # Omnibus commit SHAs are not available in the canonical repository.
          begin
            GitlabClient
              .commit(Project::OmnibusGitlab, ref: matches[:omnibus_commit])

            false
          rescue Gitlab::Error::NotFound
            true
          end
        else
          tag_name = Version.new(@version).to_omnibus(ee: true)

          begin
            GitlabClient.tag(Project::OmnibusGitlab, tag: tag_name)
            false
          rescue Gitlab::Error::NotFound
            true
          end
        end
      end
    end
  end
end
