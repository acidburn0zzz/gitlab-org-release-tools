# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::GitlabClient do
  describe 'internal client delegates' do
    let(:internal_client) { instance_double(Gitlab::Client) }

    before do
      allow(described_class).to receive(:client).and_return(internal_client)
    end

    it 'delegates .job_play' do
      expect(internal_client).to receive(:job_play)

      described_class.job_play('foo', 'bar')
    end
  end

  describe '.current_user' do
    after do
      # HACK: Prevent cross-test pollution with the `.approve_merge_request` spec
      described_class.instance_variable_set(:@current_user, nil)
    end

    it 'returns the current user', vcr: { cassette_name: 'current_user' } do
      expect(described_class.current_user).not_to be_nil
    end
  end

  describe '.pipelines', vcr: { cassette_name: 'pipelines' } do
    it 'returns project pipelines' do
      response = described_class.pipelines

      expect(response.map(&:web_url)).to all(include('/pipelines/'))
    end
  end

  describe '.cancel_redundant_pipelines', vcr: { cassette_name: 'pipelines/redundant' } do
    it 'cancels only redundant pipelines' do
      # Cancel redundant
      expect(described_class).to receive(:cancel_pipeline)
        .with('gitlab-org/gitlab-foss', 64_179_668)
      expect(described_class).to receive(:cancel_pipeline)
        .with('gitlab-org/gitlab-foss', 64_181_884)

      # Don't cancel latest running
      expect(described_class).not_to receive(:cancel_pipeline)
        .with(anything, 64_184_059)

      # Don't cancel completed
      expect(described_class).not_to receive(:cancel_pipeline)
        .with(anything, 64_165_460)

      described_class.cancel_redundant_pipelines(ref: 'master')
    end
  end

  describe '.pipeline', vcr: { cassette_name: 'pipeline' } do
    it 'returns project pipeline' do
      pipeline_id = '55053803'
      response = described_class.pipeline(ReleaseTools::Project::GitlabCe, pipeline_id)

      expect(response.web_url).to include("/pipelines/#{pipeline_id}")
    end
  end

  describe '.pipeline_jobs', vcr: { cassette_name: 'pipeline_jobs' } do
    it 'returns pipeline jobs' do
      response = described_class.pipeline_jobs(ReleaseTools::Project::GitlabCe, '55053803')

      expect(response.map(&:web_url)).to all(include('/jobs/'))
    end
  end

  describe '.pipeline_job_by_name', vcr: { cassette_name: 'pipeline_job_by_name' } do
    it 'returns first pipeline job by name' do
      job_name = 'setup-test-env'
      response = described_class.pipeline_job_by_name(ReleaseTools::Project::GitlabCe, '55053803', job_name)

      expect(response.name).to eq(job_name)
    end
  end

  describe '.job_trace', vcr: { cassette_name: 'job_trace' } do
    it 'returns job trace' do
      response = described_class.job_trace(ReleaseTools::Project::GitlabCe, '189985934')

      expect(response).to include('mkdir -p rspec_flaky/')
    end
  end

  describe '.milestones', vcr: { cassette_name: 'merge_requests/with_milestone' } do
    it 'returns a combination of project and group milestones' do
      response = described_class.milestones

      expect(response.map(&:title)).to include('9.4', '10.4')
    end
  end

  describe '.current_milestone', vcr: { cassette_name: 'milestones/all' } do
    it 'detects the earliest current milestone' do
      Timecop.travel(Date.new(2018, 5, 11)) do
        current = described_class.current_milestone

        expect(current.title).to eq('10.8')
      end
    end

    it 'falls back to MissingMilestone' do
      Timecop.travel(Date.new(2032, 8, 3)) do
        expect(described_class.current_milestone)
          .to be_kind_of(described_class::MissingMilestone)
      end
    end
  end

  describe '.milestone', vcr: { cassette_name: 'merge_requests/with_milestone' } do
    context 'when the milestone title is nil' do
      it 'returns a MissingMilestone' do
        milestone = described_class.milestone(title: nil)

        expect(milestone).to be_a(described_class::MissingMilestone)
        expect(milestone.id).to be_nil
      end
    end

    context 'when the milestone exists' do
      it 'returns the milestone' do
        response = described_class.milestone(title: '9.4')

        expect(response.title).to eq('9.4')
      end
    end

    context 'when the milestone does not exist' do
      it 'raises an exception' do
        expect { described_class.milestone(title: 'not-existent') }.to raise_error('Milestone not-existent not found for project gitlab-org/gitlab-foss!')
      end
    end
  end

  describe '.accept_merge_request' do
    before do
      allow(described_class).to receive(:current_user).and_return(double(id: 42))
    end

    let(:merge_request) do
      double(
        project: double(path: 'gitlab-org/gitlab-foss'),
        title: 'Upstream MR',
        iid: '12345',
        description: 'Hello world',
        labels: 'CE upstream',
        source_branch: 'feature',
        target_branch: 'master',
        milestone: nil)
    end

    let(:default_params) do
      {
        merge_when_pipeline_succeeds: true
      }
    end

    it 'accepts a merge request against master on the GitLab CE project' do
      expect(described_class.__send__(:client))
        .to receive(:accept_merge_request).with(
          ReleaseTools::Project::GitlabCe.path,
          merge_request.iid,
          default_params)

      described_class.accept_merge_request(merge_request)
    end

    context 'when passing a project' do
      it 'accepts a merge request in the given project' do
        expect(described_class.__send__(:client))
          .to receive(:accept_merge_request).with(
            ReleaseTools::Project::GitlabEe.path,
            merge_request.iid,
            default_params)

        described_class
          .accept_merge_request(merge_request, ReleaseTools::Project::GitlabEe)
      end
    end
  end

  describe '.create_merge_request' do
    before do
      allow(described_class).to receive_messages(
        current_user: double(id: 42),
        current_milestone: double(id: 1)
      )
    end

    let(:merge_request) do
      double(
        project: double(path: 'gitlab-org/gitlab-foss'),
        title: 'Upstream MR',
        description: 'Hello world',
        labels: 'CE upstream',
        source_branch: 'feature',
        target_branch: 'master',
        milestone: nil)
    end

    let(:default_params) do
      {
        description: merge_request.description,
        assignee_id: 42,
        labels: merge_request.labels,
        source_branch: merge_request.source_branch,
        target_branch: 'master',
        milestone_id: 1,
        remove_source_branch: true
      }
    end

    it 'creates a merge request against master on the GitLab CE project' do
      expect(described_class.__send__(:client))
        .to receive(:create_merge_request).with(
          ReleaseTools::Project::GitlabCe.path,
          merge_request.title,
          default_params)

      described_class.create_merge_request(merge_request)
    end

    context 'when passing a project' do
      it 'creates a merge request in the given project' do
        expect(described_class.__send__(:client))
          .to receive(:create_merge_request).with(
            ReleaseTools::Project::GitlabEe.path,
            merge_request.title,
            default_params)

        described_class.create_merge_request(merge_request, ReleaseTools::Project::GitlabEe)
      end
    end

    context 'when merge request has a target branch' do
      before do
        allow(merge_request).to receive(:target_branch).and_return('stable')
      end

      it 'creates a merge request against the given target branch' do
        expect(described_class.__send__(:client))
          .to receive(:create_merge_request).with(
            ReleaseTools::Project::GitlabEe.path,
            merge_request.title,
            default_params.merge(target_branch: 'stable'))

        described_class.create_merge_request(merge_request, ReleaseTools::Project::GitlabEe)
      end
    end

    context 'with milestone', vcr: { cassette_name: 'merge_requests/with_milestone' } do
      it 'sets milestone id' do
        allow(merge_request).to receive(:milestone).and_return('9.4')

        response = described_class.create_merge_request(merge_request)

        expect(response.milestone.title).to eq '9.4'
      end
    end
  end

  describe '.find_issue' do
    context 'when issue is open' do
      it 'finds issues by title', vcr: { cassette_name: 'issues/release-8-7' } do
        version = double(milestone_name: '8.7')
        issue = double(title: 'Release 8.7', labels: 'Release', version: version)

        expect(described_class.find_issue(issue)).not_to be_nil
      end
    end

    context 'when issue is closed' do
      it 'finds issues by title', vcr: { cassette_name: 'issues/regressions-8-5' } do
        version = double(milestone_name: '8.5')
        issue = double(title: '8.5 Regressions', labels: 'Release', state_filter: nil, version: version)

        expect(described_class.find_issue(issue)).not_to be_nil
      end
    end

    context 'when issue cannot be found' do
      it 'does not find non-matching issues', vcr: { cassette_name: 'issues/release-7-14' } do
        version = double(milestone_name: '7.14')
        issue = double(title: 'Release 7.14', labels: 'Release', version: version)

        expect(described_class.find_issue(issue)).to be_nil
      end
    end
  end

  describe '.find_merge_request' do
    context 'when merge request is open' do
      it 'finds merge requests by title', vcr: { cassette_name: 'merge_requests/related-issues-ux-improvments' } do
        merge_request = double(title: 'Related Issues UX improvements - loading', labels: 'Discussion')

        expect(described_class.find_merge_request(merge_request, ReleaseTools::Project::GitlabEe)).not_to be_nil
      end
    end

    context 'when merge request is merged' do
      it 'does not find merged merge requests', vcr: { cassette_name: 'merge_requests/fix-geo-middleware' } do
        merge_request = double(title: 'Fix Geo middleware to work properly with multiple requests', labels: 'geo')

        expect(described_class.find_merge_request(merge_request, ReleaseTools::Project::GitlabEe)).to be_nil
      end
    end

    context 'when merge request cannot be found' do
      it 'does not find non-matching merge requests', vcr: { cassette_name: 'merge_requests/foo' } do
        merge_request = double(title: 'Foo', labels: 'Release')

        expect(described_class.find_merge_request(merge_request, ReleaseTools::Project::GitlabEe)).to be_nil
      end
    end
  end

  describe '.link_issues' do
    let(:internal_client) { instance_double(Gitlab::Client) }

    before do
      allow(described_class).to receive(:client).and_return(internal_client)
    end

    it 'links an issue to a target' do
      issue = instance_double(
        ReleaseTools::PatchIssue,
        project: ReleaseTools::Project::GitlabCe,
        iid: 1
      )
      target = instance_double(
        ReleaseTools::MonthlyIssue,
        project: ReleaseTools::Project::GitlabEe,
        iid: 2
      )

      allow(internal_client).to receive(:url_encode)
        .with('gitlab-org/gitlab-foss')
        .and_return('gitlab-org%2Fgitlab-foss')
      expect(internal_client).to receive(:post).with(
        '/projects/gitlab-org%2Fgitlab-foss/issues/1/links',
        query: { target_project_id: 'gitlab-org/gitlab', target_issue_iid: 2 }
      )

      described_class.link_issues(issue, target)
    end
  end

  describe '.find_branch' do
    it 'finds existing branches', vcr: { cassette_name: 'branches/9-4-stable' } do
      expect(described_class.find_branch('9-4-stable').name).to eq '9-4-stable'
    end

    it "returns nil when branch can't be found", vcr: { cassette_name: 'branches/9-4-stable-doesntexist' } do
      expect(described_class.find_branch('9-4-stable-doesntexist')).to be_nil
    end
  end

  describe '.create_branch' do
    it 'creates a branch', vcr: { cassette_name: 'branches/create-test' } do
      branch_name = 'test-branch-from-release-tools'

      response = described_class.create_branch(branch_name, 'master')

      expect(response.name).to eq branch_name
    end
  end

  describe '.cherry_pick' do
    context 'on a successful pick' do
      it 'returns a reasonable response', vcr: { cassette_name: 'cherry_pick/success' } do
        ref = '59af98f133ee229479c6159b15391deb4782a294'

        response = described_class.cherry_pick(ref: ref, target: '11-4-stable')

        expect(response.message).to include("cherry picked from commit #{ref}")
      end
    end

    context 'on a failed pick' do
      it 'raises an exception', vcr: { cassette_name: 'cherry_pick/failure' } do
        expect do
          described_class.cherry_pick(
            ref: '396d205e5a503f9f48c223804087a80f7acc6d06',
            target: '11-4-stable'
          )
        end.to raise_error(Gitlab::Error::BadRequest)
      end
    end
  end

  describe '.project_path' do
    it 'returns the correct project path' do
      project = double(path: 'foo/bar')

      expect(described_class.project_path(project)).to eq 'foo/bar'
    end

    it 'returns a String unmodified' do
      project = 'gitlab-org/security/gitlab'

      expect(described_class.project_path(project)).to eq(project)
    end
  end

  describe '.related_merge_requests' do
    it 'returns the related merge requests' do
      page = double(:page)

      allow(described_class.client)
        .to receive(:get)
        .with('/projects/foo%2Fbar/issues/1/related_merge_requests')
        .and_return(page)

      expect(described_class.related_merge_requests('foo/bar', 1)).to eq(page)
    end
  end

  describe '#first_successful_auto_deployment_pipeline' do
    it 'returns the first auto-deployment pipeline' do
      pipeline1 = double(:pipeline, ref: 'foo')
      pipeline2 = double(:pipeline, ref: '12-9-auto-deploy-20200218')

      allow(described_class)
        .to receive(:pipelines)
        .and_return([pipeline1, pipeline2])

      got = described_class
        .first_successful_auto_deployment_pipeline('gitlab-org/gitlab', '123')

      expect(got).to eq(pipeline2)
    end
  end
end
