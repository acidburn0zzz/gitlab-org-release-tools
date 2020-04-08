# frozen_string_literal: true

module ReleaseTools
  # A collection of records containing data about releases of GitLab and its
  # components, such as the version and SHA that was released.
  class ReleaseMetadata
    # A regex to use for testing if a version is in a format suitable for Git
    # tags.
    TAG_REGEX = %r{
      (?<prefix>\w?)
      (?<major>\d+)
      \.
      (?<minor>\d+)
      \.
      (?<patch>\d+)
      (-rc?(?<rc>\d+))?
    }x.freeze

    # The default ref (e.g. a branch name) to use for auto-deployed components.
    #
    # If a component is released from a tag, the ref is to be set to the tag
    # name instead of this default value.
    DEFAULT_COMPONENT_REF = 'master'

    # Data about a single version/release, such as the version itself, the Git
    # ref that was released, etc.
    Release =
      Struct.new(:name, :version, :sha, :ref, :tag, keyword_init: true) do
        def tag?
          tag == true
        end
      end

    # Names of component files that are auto-deployed, and the project classes
    # they should be mapped to.
    #
    # If a component is not in this Array, it will still be tracked but:
    #
    # 1. It's name will be generated based on the version file.
    # 2. If the version is a MAJOR.MINOR.PATCH version, the SHA will not be
    #    retrieved.
    AUTO_DEPLOY_COMPONENTS = [
      Project::Gitaly,
      Project::GitlabElasticsearchIndexer,
      Project::GitlabPages,
      Project::GitlabShell,
      Project::GitlabWorkhorse
    ]
      .map { |project| [project.version_file, project] }
      .to_h
      .freeze

    # These component names will be ignored, for example because they are
    # manually added.
    #
    # VERSION and GITLAB_VERSION are ignored here because for GitLab we record
    # the release manually, allowing us to specify the correct auto-deploy
    # branch.
    IGNORED_AUTO_DEPLOY_COMPONENTS = Set.new(%w[VERSION GITLAB_VERSION]).freeze

    attr_reader :releases

    def initialize
      @releases = []
    end

    def add_release(**kwargs)
      @releases.push(Release.new(**kwargs))
    end

    # Adds the version data for all components included in a GitLab auto-deploy.
    #
    # The `mapping` argument is a `Hash` that maps component version files (e.g.
    # `VERSION`) to the corresponding version identifiers for that component.
    # For example:
    #
    #     { 'GITALY_SERVER_VERSION' => '456abc' }
    def add_auto_deploy_components(mapping)
      mapping.each do |version_file, version|
        next if IGNORED_AUTO_DEPLOY_COMPONENTS.include?(version_file)

        project = AUTO_DEPLOY_COMPONENTS[version_file]

        name =
          if project
            project.project_name
          else
            # If the component is not explicitly known we still want to track
            # it. In this case we normalise the name, and just take the input
            # version data as-is.
            version_file.downcase.gsub('_version', '')
          end

        normalized_version = version.start_with?('v') ? version[1..-1] : version
        tag = false
        ref = DEFAULT_COMPONENT_REF
        sha = nil
        valid_major_minor = version.match?(TAG_REGEX)

        if project && valid_major_minor
          tag = true
          ref = "v#{normalized_version}"
          sha = sha_of_tag(project, ref)
        elsif valid_major_minor
          # The version format is valid, but there is no project; just take the
          # version as-is.
        elsif version.length == 40
          # Our SHAs are always 40 characters long, so we can just check for the
          # length instead of using a regular expression.
          sha = version
        else
          raise ArgumentError, "The #{version_file} version #{version} is not supported"
        end

        add_release(
          name: name,
          version: normalized_version,
          sha: sha,
          ref: ref,
          tag: tag
        )
      end
    end

    def sha_of_tag(project, tag)
      path = project.security_path

      # We use the security repositories since commits from both the canonical
      # and public repositories are available there.
      project.security_client.tag(path, tag: tag).commit.id
    rescue Gitlab::Error::NotFound
      raise ArgumentError, "The tag #{tag} does not exist for project #{path}"
    end
  end
end
