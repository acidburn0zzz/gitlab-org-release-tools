# frozen_string_literal: true

module ReleaseTools
  module Changelog
    # ManagerApi collects the unreleased changelog entries from a Version's stable
    # branch, and then performs the following actions:
    #
    # 1. Compiles their contents into Markdown, updating the overall changelog
    #    document(s).
    # 2. Removes them from the repository.
    # 3. Commits the changes.
    #
    # These steps are performed on both the stable _and_ the `master` branch,
    # keeping them in sync.
    #
    # Because `master` is never merged into a `stable` branch, we aren't concerned
    # with the commits differing.
    #
    # In the case of an EE release, things get slightly more complex. We perform
    # the same steps above with the EE paths (e.g., `CHANGELOG-EE.md` and
    # `changes/unreleased-ee/`), then perform them _again_ but with the CE paths
    # (e.g., `CHANGELOG.md` and `changes/unreleased/`).
    #
    # This is necessary because by the time this process is performed, CE has
    # already been merged into EE without the consolidated `CHANGELOG.md`.
    class ManagerApi
      include ::SemanticLogger::Loggable

      attr_reader :client, :version

      def initialize(client, project, changelog_file = nil, params = {})
        @client = client
        @project = project
        @changelog_file = changelog_file
        @params = params
      end

      def release(version, stable_branch: version.stable_branch, skip_master: false)
        @unreleased_entries = nil
        @version = version

        fetch_entries(prefixed_branch(stable_branch))

        perform_release(prefixed_branch(stable_branch))
        perform_release(prefixed_branch('master')) unless skip_master

        # Recurse to perform the CE release if we're on EE
        # NOTE: We pass the EE stable branch, but use the CE configuration!
        release(version.to_ce, stable_branch: version.stable_branch) if version.ee?
      end

      private

      attr_reader :unreleased_entries

      # When performing a Security Release, protected branches should be
      # prefixed with `security/`. For the 1st iteration, we're moving
      # the security development as-is to GitLab.com, so this change is
      # not included.
      #
      # Code was not deleted so it can be easily introduced in upcoming
      # iterations.
      def prefixed_branch(name)
        name
      end

      def changelog_file
        @changelog_file || Config.log(ee: version.ee?)
      end

      def unreleased_paths
        Config.paths(ee: version.ee?)
      end

      def perform_release(branch_name)
        Retriable.retriable(on: Gitlab::Error) do
          actions = [update_changelog(branch_name)]
          actions += remove_processed_entries

          create_commit(branch_name, actions)
        end
      end

      # Updates `changelog_file` with the Markdown built from the individual
      # unreleased changelog entries.
      #
      # Raises `NoChangelogError` if the changelog blob does not exist.
      def update_changelog(branch_name)
        markdown = MarkdownGenerator.new(version, unreleased_entries, **@params).to_s

        file = client.get_file(@project, changelog_file, branch_name)
        content =
          if file.encoding == "base64"
            Base64.decode64(file.content)
          else
            logger.warn("Unexpected content encoding", project: @project, file: changelog_file, encoding: file.encoding)
            client.file_contents(@project, changelog_file, branch_name)
          end

        updater = Updater.new(content, version)

        {
          action: 'update',
          file_path: changelog_file,
          last_commit_id: file.last_commit_id,
          content: updater.insert(markdown)
        }
      rescue Gitlab::Error::NotFound
        logger.error('Can\'f find file', project: @project, file: changelog_file, branch: branch_name)
        raise ::ReleaseTools::Changelog::NoChangelogError.new(changelog_file)
      end

      def remove_processed_entries
        unreleased_entries.map do |entry|
          {
            action: 'delete',
            file_path: entry.path
          }
        end
      end

      def create_commit(branch_name, actions)
        if SharedStatus.dry_run?

          logger.warn("Dry run: will not commit")
          actions.each do |action|
            logger.info("Action", action)
          end

          return
        end

        client.create_commit(
          @project,
          branch_name,
          "Update #{changelog_file} for #{version}\n\n[ci skip]",
          actions
        )
      end

      def fetch_entries(branch_name)
        @unreleased_entries = []

        unreleased_paths.each do |path|
          client.tree(@project, ref: branch_name, path: path).auto_paginate do |entry|
            next unless entry.name.end_with?(Config.extension)

            @unreleased_entries << Entry.new(
              entry.path,
              client.file_contents(@project, entry.path, branch_name)
            )
          end
        end

        @unreleased_entries
      end
    end
  end
end
