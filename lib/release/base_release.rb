require 'colorize'
require 'forwardable'

require_relative '../changelog'
require_relative '../release'
require_relative '../repository'
require_relative '../version'

module Release
  class BaseRelease
    extend Forwardable

    attr_reader :version, :remotes, :options

    def_delegator :version, :tag
    def_delegator :version, :stable_branch

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
    def remotes
      raise NotImplementedError
    end

    def repository
      @repository ||= Repository.get(remotes)
    end

    def prepare_release
      $stdout.puts "Prepare repository...".colorize(:green)
      repository.ensure_branch_exists(stable_branch)
      repository.pull_from_all_remotes(stable_branch)
    end

    # Overridable
    def before_execute_hook
      true
    end

    def execute_release
      bump_versions
      push_ref('branch', stable_branch)
      create_tag(tag)
      push_ref('tag', tag)
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
      $stdout.puts "Update #{file_name} to #{version}...".colorize(:green)
      repository.write_file(file_name, "#{version}\n")
      repository.commit(file_name, "Update #{file_name} to #{version}")
    end

    def create_tag(tag)
      $stdout.puts "Create git tag #{tag}...".colorize(:green)
      repository.create_tag(tag)
    end

    def push_ref(ref_type, ref)
      $stdout.puts "Push #{ref_type} #{ref} to all remotes...".colorize(:green)
      repository.push_to_all_remotes(ref)
    end

    def compile_changelog
      begin
        Changelog::Manager.new(repository.path).release(version)
      rescue Changelog::NoChangelogError => ex
        $stderr.puts "Cannot perform changelog update for #{version} on " \
          "#{ex.changelog_path}".colorize(:red)
      end
    end
  end
end
