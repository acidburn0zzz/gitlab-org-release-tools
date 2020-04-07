# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Commits do
  let(:project) { ReleaseTools::Project::GitlabCe }

  before do
    # Reduce our fixture payload
    stub_const('ReleaseTools::Commits::MAX_COMMITS_TO_CHECK', 5)
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

    context 'when a limit is provided' do
      it 'returns a commit found on dev' do
        enable_feature(:merge_base_limit)
        instance = described_class.new(project)

        VCR.use_cassette('commits/list') do
          commit = instance.latest_successful_on_build(limit: 'a5f13e591f617931434d66263418a2f26abe3abe')

          expect(commit).to be_nil
        end
      end
    end
  end

  describe '#merge_base' do
    let(:project) { ReleaseTools::Project::GitlabEe }
    let(:ref) { '12-10-auto-deploy-20200405' }
    let(:client) { double('ReleaseTools::GitlabClient') }

    subject(:commits) { described_class.new(project, client: client, ref: ref) }

    it 'returns the merge-base commit id' do
      enable_feature(:merge_base_limit)
      merge_base = double('merge_base', id: '123abc')

      expect(client).to receive(:merge_base)
                          .with(project, [ref, 'another_ref'])
                          .and_return(merge_base)
                          .once

      merge_base_id = commits.merge_base('another_ref')

      expect(merge_base_id).to eq(merge_base.id)
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
                          .with(project, ref: commit.id)
                          .and_return(commit)
                          .once
      expect(client).not_to receive(:pipeline_jobs)

      expect(success?(commit)).to be true
    end

    it 'returns false when status is not success' do
      commit = double('commit', id: 'abc', status: 'skipped')

      expect(client).to receive(:commit)
                          .with(project, ref: commit.id)
                          .and_return(commit)
                          .once
      expect(client).not_to receive(:pipeline_jobs)

      expect(success?(commit)).to be false
    end

    context 'when the project is GitLab' do
      let(:project) { ReleaseTools::Project::GitlabEe }

      it 'also checks if the pipeline is a full pipeline when status is success' do
        commit = double('commit', id: 'abc', status: 'success', last_pipeline: double('pipeline', id: 1))

        job1 = double(:job, name: 'compile-assets')
        job2 = double(:job, name: 'setup-test-env')
        page = Gitlab::PaginatedResponse.new([job1, job2])

        expect(client).to receive(:commit)
                            .with(project, ref: commit.id)
                            .and_return(commit)
                            .once
        expect(client).to receive(:pipeline_jobs)
                            .with(project, 1)
                            .and_return(page)
                            .once

        expect(success?(commit)).to be true
      end

      it 'returns false when the pipeline is not a full pipeline' do
        commit = double('commit', id: 'abc', status: 'success', last_pipeline: double('pipeline', id: 1))

        job1 = double(:job, name: 'compile-assets')
        job2 = double(:job, name: 'docs lint')
        page = Gitlab::PaginatedResponse.new([job1, job2])

        expect(client).to receive(:commit)
                            .with(project, ref: commit.id)
                            .and_return(commit)
                            .once
        expect(client).to receive(:pipeline_jobs)
                            .with(project, 1)
                            .and_return(page)
                            .once

        expect(success?(commit)).to be false
      end

      it 'does not check the # of jobs when status is not success' do
        commit = double('commit', id: 'abc', status: 'skipped')

        expect(client).to receive(:commit)
                            .with(project, ref: commit.id)
                            .and_return(commit)
                            .once
        expect(client).not_to receive(:pipeline_jobs)

        expect(success?(commit)).to be false
      end
    end
  end
end
