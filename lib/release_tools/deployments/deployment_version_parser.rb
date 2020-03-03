# frozen_string_literal: true

module ReleaseTools
  module Deployments
    # Class for parsing deployment versions into a SHA, and branch/tag name.
    #
    # # Examples
    #
    # Parsing an auto-deploy version:
    #
    #     version = DeploymentVersionParser
    #       .new
    #       .parse('12.7.202001101501-94b8fd8d152.6fea3031ec9')
    #
    #     version.sha  # => "94b8fd8d152680445ec14241f14d1e4c04b0b5ab"
    #     version.ref  # => "master"
    #     version.tag? # => false
    #
    # Parsing a tag:
    #
    #     version = DeploymentVersionParser.new.parse('12.5.0-rc43.ee.0')
    #
    #     version.sha  # => "6614791fadf7a479aea05dada8488d1f64bdb43d"
    #     version.ref  # => "v12.5.0-rc43-ee"
    #     version.tag? # => true
    class DeploymentVersionParser
      # The regular expression to use for extracting the name of a deployed tag.
      TAG_REGEX = /
        (?<major>\d+)
        \.
        (?<minor>\d+)
        \.
        (?<patch>\d+)
        (-rc?(?<rc>\d+))?
      /x.freeze

      # The default ref/branch to use when none can be found for a deployed SHA.
      DEFAULT_REF = 'master'

      DeploymentVersion = Struct.new(:sha, :ref, :tag) do
        alias_method :tag?, :tag
      end

      # Parses the supplied version into a `DeploymentVersion`, which contains:
      #
      # * The deployed SHA
      # * The deployed branch or tag name
      # * A boolean indicating if a tag was deployed instead of a branch
      #
      # This method will raise an ArgumentError if the version could not be
      # parsed.
      def parse(version)
        if (parsed = deployment_from_version(version))
          return parsed
        end

        if (parsed = deployment_from_tag(version))
          return parsed
        end

        raise(ArgumentError, "Failed to extract deploy details from #{version}")
      end

      private

      def deployment_from_version(version)
        matches = version.match(Qa::Ref::AUTO_DEPLOY_TAG_REGEX)

        return unless matches && matches[:commit]

        sha = fetch_complete_sha(matches[:commit])
        ref = GitlabClient.first_successful_auto_deployment_pipeline(
          Project::GitlabEe.canonical_or_security_path,
          sha
        )&.ref

        DeploymentVersion.new(sha, ref || DEFAULT_REF, false)
      end

      def deployment_from_tag(version)
        tag = tag_for_version(version)

        DeploymentVersion.new(tag.commit.id, tag.name, true) if tag
      end

      def fetch_complete_sha(short_sha)
        GitlabClient.commit(
          Project::GitlabEe.canonical_or_security_path,
          ref: short_sha
        ).id
      end

      def tag_for_version(version)
        matches = version.match(TAG_REGEX)

        return if matches.nil?

        suffix = matches[:rc] ? "rc#{matches[:rc]}-ee" : 'ee'

        tag_name =
          "v#{matches[:major]}.#{matches[:minor]}.#{matches[:patch]}-#{suffix}"

        begin
          GitlabClient
            .tag(Project::GitlabEe.canonical_or_security_path, tag: tag_name)
        rescue Gitlab::Error::Error
          nil
        end
      end
    end
  end
end
