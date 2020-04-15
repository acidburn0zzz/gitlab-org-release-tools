# frozen_string_literal: true

module ReleaseTools
  module Release
    class GitlabBasedRelease < BaseRelease
      class VersionFileDoesNotExistError < StandardError; end

      def initialize(version, opts = {})
        super(version, opts)

        check_required_parameters!
      end

      def read_file_from_gitlab_repo(file_name)
        gitlab_file_path = File.join(gitlab_repo_path, file_name)

        ensure_version_file_exists!(gitlab_file_path)

        File.read(gitlab_file_path).strip
      end

      def version_string(version)
        # Prepend 'v' if version is semver
        return "v#{version}" if /^\d+\.\d+\.\d+(-rc\d+)?(-ee)?$/.match?(version)

        version.to_s
      end

      def version_string_from_file(file_name)
        version_string(read_file_from_gitlab_repo(file_name))
      end

      def ensure_version_file_exists!(filename)
        raise VersionFileDoesNotExistError.new(filename) unless File.exist?(filename)
      end

      def gitlab_repo_path
        options[:gitlab_repo_path]
      end

      # Overridable
      def check_required_parameters!
        raise ArgumentError, "missing gitlab_repo_path" unless gitlab_repo_path
      end
    end
  end
end
