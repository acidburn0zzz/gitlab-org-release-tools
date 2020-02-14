# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::RemoteRepository do
  include RuggedMatchers

  let(:fixture) { ReleaseFixture.new }
  let(:repo_path) { File.join(Dir.tmpdir, fixture.class.repository_name) }
  let(:rugged_repo) { Rugged::Repository.new(repo_path) }
  let(:repo_url) { "file://#{fixture.fixture_path}" }
  let(:repo_remotes) do
    { canonical: repo_url, foo: 'https://example.com/foo/bar/baz.git' }
  end

  before do
    fixture.rebuild_fixture!
  end

  describe '.get' do
    let(:remotes) do
      {
        dev:    'https://example.com/foo/bar/dev.git',
        canonical: 'https://gitlab.com/gitlab-org/foo/gitlab.git'
      }
    end

    it 'generates a name from the first remote' do
      expect(described_class).to receive(:new).with("#{Dir.tmpdir}/dev", anything, anything)

      described_class.get(remotes)
    end

    it 'accepts a repository name' do
      expect(described_class).to receive(:new).with("#{Dir.tmpdir}/foo", anything, anything)

      described_class.get(remotes, 'foo')
    end

    it 'passes remotes to the initializer' do
      expect(described_class).to receive(:new).with(anything, remotes, anything)

      described_class.get(remotes)
    end

    it 'accepts a :global_depth option' do
      expect(described_class).to receive(:new)
        .with(anything, anything, a_hash_including(global_depth: 100))

      described_class.get(remotes, global_depth: 100)
    end
  end

  describe 'initialize' do
    it 'performs cleanup' do
      expect_any_instance_of(described_class).to receive(:cleanup)

      described_class.new(repo_path, {})
    end

    it 'performs a shallow clone of the repository' do
      described_class.new(repo_path, repo_remotes)

      # Note: Rugged has no clean way to do this, so we'll shell out
      expect(`git -C #{repo_path} log --oneline | wc -l`.to_i)
        .to eq(1)
    end

    it 'adds remotes to the repository' do
      expect_any_instance_of(described_class).to receive(:remotes=)
        .with(:remotes)

      described_class.new('foo', :remotes)
    end

    it 'assigns path' do
      repository = described_class.new('foo', {})

      expect(repository.path).to eq 'foo'
    end
  end

  describe '#remotes=' do
    it 'assigns the canonical remote' do
      remotes = { canonical: repo_url }

      repository = described_class.new(repo_path, remotes)

      expect(repository.canonical_remote.name).to eq(:canonical)
      expect(repository.canonical_remote.url).to eq(repo_url)
    end

    it 'assigns remotes' do
      remotes = { canonical: repo_url }

      repository = described_class.new(repo_path, remotes)

      expect(repository.remotes).to eq(remotes)
    end

    it 'adds remotes to the repository', :aggregate_failures do
      remotes = {
        canonical: repo_url,
        foo: '/foo/bar/baz.git'
      }

      repository = described_class.new(repo_path, remotes)
      rugged = Rugged::Repository.new(repository.path)

      expect(rugged.remotes.count).to eq(2)
      expect(rugged.remotes['canonical'].url).to eq(repo_url)
      expect(rugged.remotes['foo'].url).to eq('/foo/bar/baz.git')
    end
  end

  describe '#ensure_branch_exists' do
    subject { described_class.get(repo_remotes) }

    context 'with an existing branch' do
      it 'fetches and checks out the branch with the configured global depth', :aggregate_failures do
        subject.ensure_branch_exists('branch-1')

        expect(rugged_repo).to have_head('branch-1')
        expect(rugged_repo).to have_blob('README.md').with('Sample README.md')
        expect(`git -C #{repo_path} log --oneline | wc -l`.to_i).to eq(1)
      end
    end

    context 'with a non-existing branch' do
      it 'creates and checks out the branch with the configured global depth', :aggregate_failures do
        subject.ensure_branch_exists('branch-2')

        expect(rugged_repo).to have_head('branch-2')
        expect(rugged_repo).to have_blob('README.md').with('Sample README.md')
        expect(`git -C #{repo_path} log --oneline | wc -l`.to_i).to eq(1)
      end
    end
  end

  describe '#fetch' do
    subject { described_class.get(repo_remotes) }

    it 'fetches the branch with the default configured global depth' do
      subject.fetch('branch-1')

      expect(`git -C #{repo_path} log --oneline refs/heads/branch-1 | wc -l`.to_i).to eq(1)
    end

    context 'with a depth option given' do
      it 'fetches the branch up to the given depth' do
        subject.fetch('branch-1', depth: 2)

        expect(`git -C #{repo_path} log --oneline refs/heads/branch-1 | wc -l`.to_i).to eq(2)
      end
    end
  end

  describe '#checkout_new_branch' do
    subject { described_class.get(repo_remotes) }

    it 'creates and checks out a new branch' do
      subject.checkout_new_branch('new-branch')

      expect(rugged_repo).to have_version('pages').at('4.5.0')
    end

    context 'with a given base branch' do
      it 'creates and checks out a new branch based on the given base branch' do
        subject.checkout_new_branch('new-branch', base: '9-1-stable')

        expect(rugged_repo).to have_version('pages').at('4.4.4')
      end
    end
  end

  describe '#create_tag' do
    subject { described_class.get(repo_remotes) }

    it 'creates the tag in the current branch' do
      subject.ensure_branch_exists('branch-1')
      subject.create_tag('v42')

      expect(rugged_repo.tags['v42'].target).to eq(rugged_repo.branches['branch-1'].target)
    end

    it 'uses the default tag message if not explicitly specified' do
      subject.create_tag('v42')

      expect(rugged_repo.tags['v42'].annotation.message.strip).to eq("Version v42")
    end

    it 'uses specified tag message' do
      subject.create_tag('v42', message: 'This is a tag message')

      expect(rugged_repo.tags['v42'].annotation.message.strip).to eq("This is a tag message")
    end
  end

  describe '#write_file' do
    subject { described_class.get(repo_remotes) }

    context 'with an existing file' do
      it 'overwrites the file' do
        subject.write_file('README.md', 'Cool')

        expect(File.read(File.join(repo_path, 'README.md'))).to eq 'Cool'
      end
    end

    context 'with a non-existing file' do
      it 'creates the file' do
        subject.write_file('PROCESS.md', 'Just do it!')

        expect(File.read(File.join(repo_path, 'PROCESS.md'))).to eq 'Just do it!'
      end
    end
  end

  describe '#commit' do
    subject { described_class.get(repo_remotes) }

    before do
      subject.ensure_branch_exists('branch-1')
      subject.write_file('README.md', 'Cool')
      subject.write_file('CONTRIBUTING.md', 'Be nice!')
    end

    it 'commits the given files with the given message in the current branch' do
      expect(
        subject.commit(%w[README.md CONTRIBUTING.md],
          message: 'Update README and CONTRIBUTING')
      ).to be(true)

      expect(rugged_repo).to have_commit_title('Update README and CONTRIBUTING')
      expect(rugged_repo).to have_blob('README.md').with('Cool')
      expect(rugged_repo).to have_blob('CONTRIBUTING.md').with('Be nice!')
    end

    context 'when no_edit: true and amend: true are set' do
      it 'commits the given files and amend the last commit in the current branch' do
        expect(
          subject.commit(%w[README.md CONTRIBUTING.md],
            no_edit: true,
            amend: true)
        ).to be(true)

        expect(rugged_repo).to have_commit_title(
          'Add GITLAB_SHELL_VERSION, GITLAB_WORKHORSE_VERSION, GITALY_SERVER_VERSION, GITLAB_ELASTICSEARCH_INDEXER_VERSION, VERSION'
        )

        expect(rugged_repo).to have_blob('README.md').with('Cool')
        expect(rugged_repo).to have_blob('CONTRIBUTING.md').with('Be nice!')
      end
    end

    context 'when :author is set' do
      it 'commits the given files and amends the last commit in the current branch' do
        expect(
          subject.commit(%w[README.md CONTRIBUTING.md],
            message: 'Update README and CONTRIBUTING',
            author: 'Your Name <author@example.com>')
        ).to be(true)

        expect(rugged_repo).to have_blob('README.md').with('Cool')
        expect(rugged_repo).to have_blob('CONTRIBUTING.md').with('Be nice!')

        log_lines = subject.log(format: :author)

        expect(log_lines).to start_with("Your Name\n")
      end
    end

    context 'when the Git command fails' do
      let(:error) { 'error message' }

      before do
        allow(subject).to receive(:run_git).with(%w[add README.md])
        expect(subject).to receive(:run_git).with(%w[commit])
          .and_return([error, double(success?: false)])
      end

      it 'raises a CannotCommitError exception' do
        expect { subject.commit(%w[README.md]) }
          .to raise_error(ReleaseTools::RemoteRepository::CannotCommitError, error)
      end
    end
  end

  describe '#merge' do
    subject { described_class.get(repo_remotes, global_depth: 10) }

    before do
      subject.fetch('master')
      subject.ensure_branch_exists('branch-1')
      subject.ensure_branch_exists('branch-2')
      subject.write_file('README.md', 'Nice')
      subject.commit('README.md', message: 'Update README.md')
      subject.ensure_branch_exists('branch-1')
    end

    it 'commits the given files with the given message in the current branch' do
      expect(subject.merge('branch-2', no_ff: true).status).to be_success
      log = subject.log(format: :message)

      expect(log).to start_with("Merge branch 'branch-2' into branch-1\n")
      expect(File.read(File.join(repo_path, 'README.md'))).to eq 'Nice'
    end

    it 'performs an octopus merge with an array of commits' do
      subject.write_file('foo', 'bar')
      subject.commit('foo', message: 'Add foo')

      subject.ensure_branch_exists('branch-3')

      expect(subject.merge(['branch-1', 'branch-2'], no_ff: true).status).to be_success
      log = subject.log(format: :message)

      expect(File.read(File.join(repo_path, 'README.md'))).to eq 'Nice'
      expect(File.read(File.join(repo_path, 'foo'))).to eq 'bar'
      expect(log).to start_with("Merge branches 'branch-1' and 'branch-2' into branch-3\n")
    end

    context 'when a target branch is specified' do
      it 'checkout into the given branch' do
        expect(subject.merge('branch-2', into: 'master', no_ff: true).status).to be_success

        expect(rugged_repo).to have_head('master')
        expect(rugged_repo).to have_commit_title("Merge branch 'branch-2'")
        expect(rugged_repo).to have_blob('README.md').with('Nice')
      end

      it 'raises an error if the branch does not exist' do
        expect { subject.merge('branch-2', into: 'not-existing-branch') }
          .to raise_error(ReleaseTools::RemoteRepository::CannotCheckoutBranchError)
      end
    end
  end

  describe '#tags' do
    subject { described_class.get(repo_remotes) }

    it 'calls "git tag --list"' do
      allow(subject).to receive(:fetch).and_return true
      expect(subject).to receive(:run_git).with(%w[tag --list]).and_call_original

      subject.tags
    end

    context 'when :sort is set' do
      it 'sorts tags by the given format' do
        allow(subject).to receive(:fetch).and_return true
        expect(subject).to receive(:run_git).with(%w[tag --list --sort='-v:refname']).and_call_original

        subject.tags(sort: '-v:refname')
      end
    end
  end

  describe '#tag_messages' do
    subject { described_class.get(repo_remotes) }

    it 'returns hash of tags and messages' do
      expect(subject.tag_messages).to eq(
        "v9.1.0" => "GitLab Version 9.1.0",
        "v1.9.0" => "GitLab Version 1.9.0"
      )
    end
  end

  describe '#status' do
    subject { described_class.get(repo_remotes) }

    before do
      subject.ensure_branch_exists('branch-1')
      subject.write_file('README.md', 'Cool')
      subject.write_file('CONTRIBUTING.md', 'Be nice!')
    end

    it 'calls "git log"' do
      expect(subject).to receive(:run_git).with(%w[status])

      subject.status
    end

    context 'when short is true' do
      it 'shows the modified files in the short form' do
        expect(subject).to receive(:run_git).with(%w[status --short])

        subject.status(short: true)
      end
    end
  end

  describe '#log' do
    subject { described_class.get(repo_remotes, global_depth: 10) }

    before do
      subject.fetch('master', depth: 10)
      subject.checkout_new_branch('branch-1')
      subject.checkout_new_branch('branch-2')
      subject.write_file('README.md', 'Nice')
      subject.commit('README.md', message: 'Update README.md')
      subject.ensure_branch_exists('branch-1')
      subject.merge('branch-2', no_ff: true)
    end

    it 'shows commits' do
      expect(subject).to receive(:run_git).with(%w[log --topo-order])

      subject.log
    end

    context 'when latest is true' do
      it 'shows only the latest commit' do
        expect(subject).to receive(:run_git).with(%w[log --topo-order -1])

        subject.log(latest: true)
      end
    end

    context 'when no_merges is true' do
      it 'shows non-merge commits' do
        expect(subject).to receive(:run_git).with(%w[log --topo-order --no-merges])

        subject.log(no_merges: true)
      end
    end

    context 'when format is author' do
      it 'shows authors only' do
        expect(subject).to receive(:run_git).with(%w[log --topo-order --format='%aN'])

        subject.log(format: :author)
      end
    end

    context 'when format is message' do
      it 'shows messages only' do
        expect(subject).to receive(:run_git).with(%w[log --topo-order --format='%B'])

        subject.log(format: :message)
      end
    end

    context 'when :paths is set' do
      it 'shows commits for the given file when :paths is a string' do
        expect(subject).to receive(:run_git).with(%w[log --topo-order -- README.md])

        subject.log(paths: 'README.md')
      end

      it 'shows commits for the given files when :paths is an array' do
        expect(subject).to receive(:run_git).with(%w[log --topo-order -- README.md VERSION])

        subject.log(paths: %w[README.md VERSION])
      end
    end
  end

  describe '#head' do
    subject { described_class.get(repo_remotes) }

    before do
      subject.ensure_branch_exists('branch-1')
    end

    it 'shows current HEAD sha' do
      expect(subject.head).to eq(`git -C #{repo_path} rev-parse --verify HEAD`.strip)
    end
  end

  describe '#pull' do
    subject { described_class.get(repo_remotes) }

    before do
      subject.ensure_branch_exists('master')
    end

    it 'pulls the branch with the configured depth' do
      expect { subject.pull('master') }
        .not_to(change { subject.log(format: :message).lines.size })
    end

    context 'with a depth option given' do
      it 'pulls the branch with to the given depth' do
        expect { subject.pull('master', depth: 2) }
          .to change { subject.log(format: :message).lines.size }.from(1).to(2)
      end
    end
  end

  describe '#pull_from_all_remotes' do
    subject { described_class.get(Hash[*repo_remotes.first]) }

    context 'when there are conflicts' do
      it 'raises a CannotPullError error' do
        allow(subject).to receive(:conflicts?).and_return(true)

        expect { subject.pull_from_all_remotes('1-9-stable') }
          .to raise_error(described_class::CannotPullError)
      end
    end

    it 'does not raise error' do
      expect { subject.pull_from_all_remotes('master') }
        .not_to raise_error
    end

    context 'with a depth option given' do
      it 'pulls the branch down to the given depth' do
        expect { subject.pull_from_all_remotes('master', depth: 2) }
          .to change { subject.log(format: :message).lines.size }.from(1).to(2)
      end
    end
  end

  describe '#verify_sync!' do
    it 'does nothing with only one remote' do
      repo = described_class.get(repo_remotes.slice(:canonical))

      expect(repo).not_to receive(:ls_remotes)

      repo.verify_sync!('foo')
    end

    it 'does nothing when remotes are in sync' do
      repo = described_class.get(repo_remotes)

      expect(repo).to receive(:ls_remotes).with('foo')
        .and_return(canonical: 'a', security: 'a')

      expect { repo.verify_sync!('foo') }
        .not_to raise_error
    end

    it 'raises an error when remotes are out of sync' do
      repo = described_class.get(repo_remotes)

      expect(repo).to receive(:ls_remotes).with('foo')
        .and_return(canonical: 'a', security: 'b')

      expect { repo.verify_sync!('foo') }
        .to raise_error(described_class::OutOfSyncError)
    end
  end

  describe '#cleanup' do
    it 'removes the repository path' do
      repository = described_class.new(repo_path, {})

      expect(FileUtils).to receive(:rm_rf).with(repo_path, secure: true)

      repository.cleanup
    end
  end

  describe '#changes?' do
    subject { described_class.get(repo_remotes) }

    before do
      subject.ensure_branch_exists('branch-1')
    end

    it 'returns false when no changes' do
      expect(subject.changes?).to be(false)
    end

    it 'returns true when there is untracked work' do
      subject.write_file('README.md', 'Cool')
      subject.write_file('CONTRIBUTING.md', 'Be nice!')

      expect(subject.changes?).to be(true)
    end

    it 'returns true when there is staged work' do
      subject.write_file('README.md', 'Cool')
      subject.write_file('CONTRIBUTING.md', 'Be nice!')
      subject.send(:run_git, ['add', %w[README.md CONTRIBUTING.md]])

      expect(subject.changes?).to be(true)
    end

    context 'with paths provided' do
      it 'returns false when no changes' do
        expect(subject.changes?(paths: 'README.md')).to be(false)
      end

      it 'returns true when there is referenced untracked work' do
        subject.write_file('README.md', 'Cool')
        subject.write_file('CONTRIBUTING.md', 'Be nice!')

        expect(subject.changes?(paths: %w[README.md CONTRIBUTING.md])).to be(true)
      end

      it 'returns false when there is untracked work outside the path' do
        subject.write_file('README.md', 'Cool')
        subject.write_file('CONTRIBUTING.md', 'Be nice!')

        expect(subject.changes?(paths: 'libs')).to be(false)
      end

      it 'returns true when there is referenced staged work' do
        subject.write_file('README.md', 'Cool')
        subject.write_file('CONTRIBUTING.md', 'Be nice!')
        subject.send(:run_git, ['add', %w[README.md CONTRIBUTING.md]])

        expect(subject.changes?(paths: %w[README.md CONTRIBUTING.md])).to be(true)
      end

      it 'returns false when there is staged work outside the path' do
        subject.write_file('README.md', 'Cool')
        subject.write_file('CONTRIBUTING.md', 'Be nice!')
        subject.send(:run_git, ['add', %w[README.md CONTRIBUTING.md]])

        expect(subject.changes?(paths: 'libs')).to be(false)
      end
    end
  end

  describe described_class::GitCommandError do
    it 'adds indented output to the error message' do
      error = described_class.new("Foo", "bar\nbaz")

      expect(error.message).to eq "Foo\n\n  bar\n  baz"
    end
  end
end
