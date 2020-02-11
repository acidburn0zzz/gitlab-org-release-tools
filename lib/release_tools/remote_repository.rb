# frozen_string_literal: true

module ReleaseTools
  class RemoteRepository
    include ::SemanticLogger::Loggable

    OutOfSyncError = Class.new(StandardError)

    class GitCommandError < StandardError
      def initialize(message, output = nil)
        message += "\n\n  #{output.gsub("\n", "\n  ")}" unless output.nil?

        super(message)
      end
    end

    CannotCheckoutBranchError = Class.new(GitCommandError)
    CannotCloneError = Class.new(GitCommandError)
    CannotCommitError = Class.new(GitCommandError)
    CannotCreateTagError = Class.new(GitCommandError)
    CannotPullError = Class.new(GitCommandError)

    CanonicalRemote = Struct.new(:name, :url)
    GitCommandResult = Struct.new(:output, :status)

    def self.get(remotes, repository_name = nil, global_depth: 1, branch: nil)
      repository_name ||= remotes
        .values
        .first
        .split('/')
        .last
        .sub(/\.git\Z/, '')

      new(
        File.join(Dir.tmpdir, repository_name),
        remotes,
        global_depth: global_depth,
        branch: branch
      )
    end

    attr_reader :path, :remotes, :canonical_remote, :global_depth, :branch

    def initialize(path, remotes, global_depth: 1, branch: nil)
      logger.warn("Pushes will be ignored because of TEST env") if SharedStatus.dry_run?

      @path = path
      @global_depth = global_depth
      @branch = branch

      cleanup

      # Add remotes, performing the first clone as necessary
      self.remotes = remotes
    end

    def ensure_branch_exists(branch, base: 'master')
      fetch(branch)

      checkout_branch(branch) || checkout_new_branch(branch, base: base)
    end

    def fetch(ref, remote: canonical_remote.name, depth: global_depth)
      base_cmd = %w[fetch --quiet]
      base_cmd << "--depth=#{depth}" if depth
      base_cmd << remote.to_s

      _, status = run_git([*base_cmd, "#{ref}:#{ref}"])
      _, status = run_git([*base_cmd, ref]) unless status.success?

      status.success?
    end

    def checkout_new_branch(branch, base: 'master')
      fetch(base)

      output, status = run_git %W[checkout --quiet -b #{branch} #{base}]

      status.success? || raise(CannotCheckoutBranchError.new(branch, output))
    end

    def create_tag(tag, message: nil)
      message ||= "Version #{tag}"
      output, status = run_git %W[tag -a #{tag} -m "#{message}"]

      status.success? || raise(CannotCreateTagError.new(tag, output))
    end

    def write_file(file, content)
      in_path { File.write(file, content) }
    end

    def commit(files, no_edit: false, amend: false, message: nil, author: nil)
      run_git ['add', *Array(files)] if files

      cmd = %w[commit]
      cmd << '--no-edit' if no_edit
      cmd << '--amend' if amend
      cmd << %[--author="#{author}"] if author
      cmd += ['--message', %["#{message}"]] if message

      output, status = run_git(cmd)

      status.success? || raise(CannotCommitError.new(output))
    end

    def merge(commits, into: nil, no_ff: false)
      if into
        checkout_branch(into) || raise(CannotCheckoutBranchError.new(into))
      end

      cmd = %w[merge --no-edit --no-log]
      cmd << '--no-ff' if no_ff
      cmd += Array(commits)

      GitCommandResult.new(*run_git(cmd))
    end

    def tags(sort: nil, remote: canonical_remote.name)
      fetch('refs/tags/*', remote: remote)

      cmd = %w[tag --list]
      cmd << "--sort='#{sort}'" if sort

      output, status = run_git(cmd)

      output.lines.map(&:chomp) if status.success?
    end

    def tag_messages(remote: canonical_remote.name)
      fetch('refs/tags/*', remote: remote)

      cmd = %w[tag --list --format="%(tag),%(subject)"]

      output, status = run_git(cmd)

      # Convert to a hash with the format { tag1 => message1, tag2 => message2 }
      output.lines.map { |string| string.chomp.split(',', 2) }.to_h if status.success?
    end

    def status(short: false)
      cmd = %w[status]
      cmd << '--short' if short

      output, = run_git(cmd)

      output
    end

    def log(latest: false, no_merges: false, format: nil, paths: nil)
      format_pattern =
        case format
        when :author
          '%aN'
        when :message
          '%B'
        end

      cmd = %w[log --topo-order]
      cmd << '-1' if latest
      cmd << '--no-merges' if no_merges
      cmd << "--format='#{format_pattern}'" if format_pattern
      if paths
        cmd << '--'
        cmd += Array(paths)
      end

      output, = run_git(cmd)
      output&.squeeze!("\n") if format_pattern == :message

      output
    end

    def head
      output, = run_git(%w[rev-parse --verify HEAD])

      output.chomp
    end

    def pull(ref, remote: canonical_remote.name, depth: global_depth)
      cmd = %w[pull --quiet]
      cmd << "--depth=#{depth}" if depth
      cmd << remote.to_s
      cmd << ref

      output, status = run_git(cmd)

      if conflicts?
        raise CannotPullError.new("Conflicts were found when pulling #{ref} from #{remote}", output)
      end

      status.success?
    end

    def pull_from_all_remotes(ref, depth: global_depth)
      remotes.each_key do |remote_name|
        pull(ref, remote: remote_name, depth: depth)
      end
    end

    # Verify the specified ref is the same across all remotes
    def verify_sync!(ref)
      return unless remotes.size > 1

      refs = ls_remotes(ref)

      return if refs.values.uniq.size == 1

      failure_message = refs
        .map { |k, v| "#{k}: #{v}" }
        .join(', ')
        .indent(2)

      raise OutOfSyncError, "Remotes are out of sync:\n#{failure_message}"
    end

    def push(remote, ref)
      cmd = %W[push #{remote} #{ref}:#{ref}]

      if SharedStatus.dry_run?
        logger.trace(__method__, remote: remote, ref: ref)

        true
      else
        output, status = run_git(cmd)

        if status.success?
          true
        else
          logger.warn('Failed to push', remote: remote, ref: ref, output: output)
          false
        end
      end
    end

    def push_to_all_remotes(ref)
      remotes.each_key do |remote_name|
        push(remote_name, ref)
      end
    end

    def cleanup
      logger.trace(__method__, path: path) if Dir.exist?(path)

      FileUtils.rm_rf(path, secure: true)
    end

    def changes?(paths: nil)
      cmd = %w[status --porcelain]

      if paths
        cmd << '--'
        cmd += Array(paths)
      end

      output, = run_git(cmd)

      !output.empty?
    end

    def self.run_git(args)
      final_args = ['git', *args].join(' ')

      logger.trace(__method__, command: final_args)

      cmd_output = `#{final_args} 2>&1`

      [cmd_output, $CHILD_STATUS]
    end

    private

    # Given a Hash of remotes {name: url}, add each one to the repository
    def remotes=(new_remotes)
      @remotes = new_remotes.dup
      @canonical_remote = CanonicalRemote.new(*remotes.first)

      new_remotes.each do |remote_name, remote_url|
        # Canonical remote doesn't need to be added twice
        next if remote_name == canonical_remote.name

        add_remote(remote_name, remote_url)
      end
    end

    def add_remote(name, url)
      _, status = run_git %W[remote add #{name} #{url}]

      status.success?
    end

    # Returns a Hash of remote => SHA pairs for the specified ref on all remotes
    def ls_remotes(ref)
      remotes.keys.map do |remote_name|
        output, status = run_git(%W[ls-remote #{remote_name} #{ref}])

        value = if !status.success?
                  'unknown'
                elsif output.empty?
                  output
                else
                  output.split("\t").first.strip
                end

        [remote_name, value]
      end.to_h
    end

    def checkout_branch(branch)
      _, status = run_git %W[checkout --quiet #{branch}]

      status.success?
    end

    def in_path
      Dir.chdir(path) do
        yield
      end
    end

    def conflicts?
      in_path do
        output = `git ls-files -u`
        return !output.empty?
      end
    end

    def run_git(args)
      ensure_repo_exist
      in_path do
        self.class.run_git(args)
      end
    end

    def ensure_repo_exist
      return if File.exist?(path) && File.directory?(File.join(path, '.git'))

      cmd = %w[clone --quiet]
      cmd << "--depth=#{global_depth}" if global_depth
      cmd << "--branch=#{branch}" if branch
      cmd << '--origin' << canonical_remote.name.to_s << canonical_remote.url << path

      output, status = self.class.run_git(cmd)
      unless status.success?
        raise CannotCloneError.new("Failed to clone #{canonical_remote.url} to #{path}", output)
      end
    end
  end
end
