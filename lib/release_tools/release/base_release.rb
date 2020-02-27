# frozen_string_literal: true

module ReleaseTools
  module Release
    class BaseRelease
      extend Forwardable

      include ::SemanticLogger::Loggable

      attr_reader :version, :options

      def_delegator :version, :tag

      def initialize(version, opts = {})
        @version = version_class.new(version)
        @options = opts
      end

      def execute
        prepare_release
        before_execute_hook
        execute_release
        after_execute_hook
        after_release
      end

      private

      # Overridable
      def project
        raise NotImplementedError
      end

      def remotes
        project.remotes
      end

      def repository
        @repository ||= RemoteRepository.get(remotes, global_depth: 100)
      end

      def prepare_release
        logger.info("Preparing repository...")

        repository.pull_from_all_remotes(master_branch)
        repository.ensure_branch_exists(stable_branch, base: stable_branch_base)
        repository.pull_from_all_remotes(stable_branch)
      end

      # Overridable
      def stable_branch_base
        master_branch
      end

      # Overridable
      def before_execute_hook
        true
      end

      def execute_release
        if repository.tags.include?(tag)
          logger.warn('Tag already exists, skipping', name: tag)
          return
        end

        repository.ensure_branch_exists(stable_branch)
        repository.verify_sync!(stable_branch)

        bump_versions

        push_ref('branch', stable_branch)
        push_ref('branch', master_branch)

        create_tag(tag)
        push_ref('tag', tag)

        Slack::TagNotification.release(project, version) unless SharedStatus.dry_run?
      end

      def master_branch
        'master'
      end

      def stable_branch
        version.stable_branch
      end

      # Overridable
      def after_execute_hook
        true
      end

      def after_release
        repository.cleanup
      end

      # Overridable
      def version_class
        Version
      end

      # Overridable
      def bump_versions
        bump_version('VERSION', version)
      end

      def bump_version(file_name, version)
        file = File.join(repository.path, file_name)
        return if File.read(file).chomp == version

        logger.info('Bumping version', file_name: file_name, version: version)

        repository.write_file(file_name, "#{version}\n")
        repository.commit(file_name, message: "Update #{file_name} to #{version}")
      end

      def create_tag(tag, message: nil)
        logger.info('Creating tag', name: tag)

        repository.create_tag(tag, message: message)
      end

      def push_ref(_ref_type, ref)
        logger.info('Pushing ref to remotes', name: ref, remotes: remotes.keys)

        repository.push_to_all_remotes(ref)
      end
    end
  end
end
