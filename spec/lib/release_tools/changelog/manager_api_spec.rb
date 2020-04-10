# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Changelog::ManagerApi do
  let(:config)        { ReleaseTools::Changelog::Config }
  let(:client)        { double('ReleaseTools::GitlabClient') }
  let(:project)       { ReleaseTools::Project::GitlabWorkhorse }
  let(:version)       { ReleaseTools::Version.new('8.10.5') }
  let(:stable_branch) { version.stable_branch }

  subject(:manager) { described_class.new(client, project) }

  describe '#release' do
    it 'creates the changelog' do
      # changelog entries
      gitkeep = double(:tree_file, path: 'changelog/unreleased/.gitkeep', name: '.gitkeep')
      file1 = double(:tree_file, path: 'changelog/unreleased/entry1.yml', name: 'entry1.yml')
      file2 = double(:tree_file, path: 'changelog/unreleased/entry2.yml', name: 'entry2.yml')

      tree = Gitlab::PaginatedResponse.new([gitkeep, file1, file2])
      expect(client).to receive(:tree)
                          .with(project, ref: stable_branch, path: 'changelogs/unreleased')
                         .and_return(tree)
      expect(client).to receive(:file_contents)
                          .with(project, file1.path, stable_branch)
                          .and_return('')
      expect(client).to receive(:file_contents)
                          .with(project, file2.path, stable_branch)
                          .and_return('')

      # changelog compilation
      changelog_content = Base64.encode64("# CHANGELOG\n\n## 8.10.4\n\n- Change A")

      changelog = double(:file,
                         last_commit_id: '123abc',
                         encoding: 'base64',
                         content: changelog_content)

      expect(client).to receive(:get_file)
                          .with(project, 'CHANGELOG.md', stable_branch)
                          .and_return(changelog)

      actions = [
        {
          action: 'update',
          content: match("## #{version}"),
          last_commit_id: changelog.last_commit_id,
          file_path: 'CHANGELOG.md'
        },
        { action: 'delete', file_path: file1.path },
        { action: 'delete', file_path: file2.path }
      ]
      expected_commit_message = "Update CHANGELOG.md for #{version}\n\n[ci skip]"
      expect(client).to receive(:create_commit)
                          .with(
                            project,
                            stable_branch,
                            expected_commit_message,
                            actions
                          )

      # master changelog
      expect(client).to receive(:get_file)
                          .with(project, 'CHANGELOG.md', 'master')
                          .and_return(changelog)

      expect(client).to receive(:create_commit)
                          .with(
                            project,
                            'master',
                            expected_commit_message,
                            actions
                          )

      without_dry_run do
        manager.release(version)
      end
    end
  end

  describe '#release', 'with no changelog file' do
    it 'raises NoChangelogError' do
      tree = Gitlab::PaginatedResponse.new([])
      expect(client).to receive(:tree)
                          .with(project, ref: stable_branch, path: 'changelogs/unreleased')
                          .and_return(tree)

      expect(client).to receive(:get_file)
                          .with(project, 'CHANGELOG.md', stable_branch)
                          .and_raise(gitlab_error(:NotFound))

      expect { manager.release(version) }
        .to raise_error(ReleaseTools::Changelog::NoChangelogError)
    end
  end
end
