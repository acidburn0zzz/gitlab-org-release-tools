# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Commits do
  let(:project) { ReleaseTools::Project::GitlabCe }

  before do
    # Reduce our fixture payload
    stub_const('ReleaseTools::Commits::MAX_COMMITS_TO_CHECK', 5)

    enable_feature(:security_remote)
  end

  describe '#latest_successful' do
    it 'returns the latest successful commit' do
      instance = described_class.new(project)

      VCR.use_cassette('commits/list') do
        commit = instance.latest_successful

        expect(commit.id).to eq 'a5f13e591f617931434d66263418a2f26abe3abe'
      end
    end
  end

  describe '#latest_successful_on_build' do
    it 'handles a missing commit on dev' do
      allow(ReleaseTools::GitlabDevClient)
        .to receive(:commit)
        .and_raise(gitlab_error(:NotFound))

      instance = described_class.new(project)

      VCR.use_cassette('commits/list') do
        expect(instance.latest_successful_on_build).to be_nil
      end
    end

    it 'returns a commit found on dev' do
      allow(ReleaseTools::GitlabDevClient)
        .to receive(:commit)
        .and_return('foo')

      instance = described_class.new(project)

      VCR.use_cassette('commits/list') do
        expect(instance.latest_successful_on_build).not_to be_nil
      end
    end
  end

  describe '#success?' do
    let(:project) { ReleaseTools::Project::Gitaly }
    let(:client) { double('ReleaseTools::GitlabClient') }

    def success?(commit)
      described_class.new(project, client: client).send(:success?, commit)
    end

    it 'returns true when status is success' do
      commit = double('commit', id: 'abc', status: 'success')

      expect(client).to receive(:commit)
        .with(project.security_path, ref: commit.id)
        .and_return(commit)
        .once
      expect(client).not_to receive(:pipeline_jobs)

      expect(success?(commit)).to be true
    end

    it 'returns false when status is not success' do
      commit = double('commit', id: 'abc', status: 'skipped')

      expect(client).to receive(:commit)
        .with(project.security_path, ref: commit.id)
        .and_return(commit)
        .once
      expect(client).not_to receive(:pipeline_jobs)

      expect(success?(commit)).to be false
    end

    context 'when the project is GitLab' do
      let(:project) { ReleaseTools::Project::GitlabEe }

      it 'returns false for a partial pipeline' do
        commit = double('commit', id: 'abc', status: 'success', last_pipeline: double('pipeline', id: 1))

        expect(client).to receive(:commit)
          .with(project.security_path, ref: commit.id)
          .and_return(commit)
          .once
        expect(client).to receive(:pipeline_jobs)
          .with(project.security_path, 1, per_page: 50)
          .and_return(double('jobs', has_next_page?: false))
          .once

        expect(success?(commit)).to be false
      end

      it 'returns true for a full pipeline' do
        commit = double('commit', id: 'abc', status: 'success', last_pipeline: double('pipeline', id: 1))

        expect(client).to receive(:commit)
          .with(project.security_path, ref: commit.id)
          .and_return(commit)
          .once
        expect(client).to receive(:pipeline_jobs)
          .with(project.security_path, 1, per_page: 50)
          .and_return(double('jobs', has_next_page?: true))
          .once

        expect(success?(commit)).to be true
      end
    end
  end
end
