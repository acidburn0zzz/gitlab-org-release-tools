# frozen_string_literal: true

require 'fileutils'
require 'rugged'

module RepositoryFixture
  attr_reader :fixture_path

  def initialize(fixture_path = nil)
    @fixture_path = fixture_path || default_fixture_path
  end

  def rebuild_fixture!(options = {})
    wipe_fixture!
    build_fixture(options)
  end

  def wipe_fixture!
    FileUtils.rm_r(fixture_path) if Dir.exist?(fixture_path)
    FileUtils.mkdir_p(fixture_path)
    @repository = nil
  end

  def build_fixture(options = {})
    raise NotImplementedError
  end

  def repository
    @repository ||= Rugged::Repository.init_at(fixture_path)
  end

  # When performing a Security Release, protected branches should be
  # prefixed with `security/`. For the 1st iteration, we're moving
  # the security development as-is to GitLab.com, so this change is
  # not included.
  #
  # Code was not deleted so it can be easily introduced in upcoming
  # iterations.
  def branch_prefix
    ''
  end

  private

  # Commit multiple files at once
  #
  # files - A Hash of filename => content pairs
  #
  # Returns the Rugged::Commit object
  def commit_blobs(files, message: nil, author: nil)
    index = repository.index

    files.each do |path, content|
      oid = repository.write(content, :blob)
      index.add(path: path, oid: oid, mode: 0o100644)
    end

    message ||= "Add #{files.keys.join(', ')}"

    commit = Rugged::Commit.create(
      repository,
      tree: index.write_tree(repository),
      message: message,
      author: author,
      parents: repository.empty? ? [] : [repository.head.target].compact,
      update_ref: 'HEAD'
    )

    repository.checkout_head(strategy: :force)

    commit
  end

  def commit_blob(path:, content:, message:, author: nil)
    commit_blobs({ path => content }, message: message, author: author)
  end

  # Create a `master` branch prefixed with `branch_prefix`
  #
  # The first `commit_blob` call on an empty repository will create a default
  # `master` branch, so we branch off of that, then delete the original.
  def create_prefixed_master
    return unless branch_prefix.present?

    repository.create_branch("#{branch_prefix}master", 'master')
    repository.checkout("#{branch_prefix}master")
    repository.branches.delete('master')
  end

  def default_fixture_path
    File.expand_path(
      "../fixtures/repositories/#{self.class.repository_name}",
      __dir__
    )
  end
end
