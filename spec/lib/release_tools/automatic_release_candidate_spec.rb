# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::AutomaticReleaseCandidate do
  let(:today) { Time.new(2020, 3, 9, 16) }

  def stub_release_schedule
    schedule = instance_spy(ReleaseTools::ReleaseManagers::Schedule)

    allow(ReleaseTools::ReleaseManagers::Schedule)
      .to receive(:new)
      .and_return(schedule)

    allow(schedule)
      .to receive(:version_for_date)
      .with(today)
      .and_return(ReleaseTools::Version.new('12.9'))
  end

  def stubbed_rc
    stub_release_schedule

    allow(ReleaseTools::AutoDeployBranch)
      .to receive(:current)
      .and_return('source-branch')

    ClimateControl.modify(GITLAB_BOT_PRODUCTION_TOKEN: 'hunter2') do
      described_class.new(today)
    end
  end

  describe '#initialize' do
    context 'when no release managers schedule could be found' do
      it 'raises an error' do
        schedule = instance_spy(ReleaseTools::ReleaseManagers::Schedule)

        allow(ReleaseTools::ReleaseManagers::Schedule)
          .to receive(:new)
          .and_return(schedule)

        allow(schedule)
          .to receive(:version_for_date)
          .with(today)
          .and_return(nil)

        expect { described_class.new(today) }.to raise_error(StandardError)
      end
    end

    context 'when the GITLAB_BOT_PRODUCTION_TOKEN variable is not set' do
      it 'raises an error' do
        stub_release_schedule

        expect { described_class.new(today) }.to raise_error(KeyError)
      end
    end
  end

  describe '#prepare' do
    context 'when the target branch does not exist' do
      it 'does not update the target branch' do
        rc = stubbed_rc

        allow(rc)
          .to receive(:branch_exists?)
          .with('12-9-stable-ee')
          .and_return(false)

        expect(rc).not_to receive(:create_source_branch)
        expect(rc).not_to receive(:update_target_branch)

        without_dry_run { rc.prepare }
      end
    end

    context 'when using a dry-run' do
      it 'does not create or update any data' do
        rc = stubbed_rc

        allow(rc)
          .to receive(:branch_exists?)
          .with('12-9-stable-ee')
          .and_return(true)

        expect(rc).not_to receive(:create_source_branch)
        expect(rc).not_to receive(:update_target_branch)

        ClimateControl.modify(TEST: 'true') do
          rc.prepare
        end
      end
    end

    context 'when the source and target branches are the same' do
      it 'does not update the target branch' do
        rc = stubbed_rc

        allow(rc)
          .to receive(:branch_exists?)
          .with('12-9-stable-ee')
          .and_return(true)

        allow(ReleaseTools::GitlabClient.client)
          .to receive(:compare)
          .with(described_class::PROJECT, '12-9-stable-ee', rc.source_branch)
          .and_return(double(:response, commits: []))

        expect(rc).to receive(:create_source_branch)
        expect(rc).to receive(:delete_source_branch)
        expect(rc).not_to receive(:update_target_branch)

        without_dry_run { rc.prepare }
      end
    end

    context 'when the source and target branch differ' do
      it 'updates the target branch' do
        rc = stubbed_rc

        allow(rc).to receive(:create_source_branch)

        allow(rc)
          .to receive(:branch_exists?)
          .with('12-9-stable-ee')
          .and_return(true)

        allow(ReleaseTools::GitlabClient.client)
          .to receive(:compare)
          .with(described_class::PROJECT, '12-9-stable-ee', rc.source_branch)
          .and_return(double(:response, commits: [double(:commit)]))

        expect(rc).to receive(:update_target_branch)

        without_dry_run { rc.prepare }
      end
    end
  end

  describe '#update_target_branch' do
    it 'updates the target branch using a merge request' do
      rc = stubbed_rc
      mr = double(:merge_request, web_url: 'foo', project_id: 1, iid: 2)
      pipeline1 = double(:pipeline, id: 42, status: 'running')
      pipeline2 = double(:pipeline, id: 43, status: 'created')

      expect(ReleaseTools::GitlabClient)
        .to receive(:current_user)
        .and_return(double(:user, id: 1))

      expect(ReleaseTools::GitlabClient.client)
        .to receive(:create_merge_request)
        .with(
          ReleaseTools::GitlabClient.project_path(described_class::PROJECT),
          an_instance_of(String),
          description: an_instance_of(String),
          assignee_id: 1,
          labels: 'backstage,team::Delivery',
          source_branch: rc.source_branch,
          target_branch: '12-9-stable-ee',
          remove_source_branch: true
        )
        .and_return(mr)

      expect(ReleaseTools::GitlabClient.client)
        .to receive(:merge_request_pipelines)
        .and_return(Gitlab::PaginatedResponse.new([pipeline1, pipeline2]))

      expect(ReleaseTools::GitlabClient.client)
        .to receive(:cancel_pipeline)
        .with(1, 42)

      expect(ReleaseTools::GitlabClient.client)
        .to receive(:cancel_pipeline)
        .with(1, 43)

      expect(rc.gitlab_bot_client).to receive(:approve_merge_request).with(1, 2)

      expect(rc.gitlab_bot_client)
        .to receive(:accept_merge_request)
        .with(1, 2, should_remove_source_branch: true)

      rc.update_target_branch
    end
  end

  describe '#branch_exists?' do
    it 'returns true if a branch exists' do
      rc = stubbed_rc

      expect(ReleaseTools::GitlabClient)
        .to receive(:find_branch)
        .with('foo', described_class::PROJECT)
        .and_return(double(:branch))

      expect(rc.branch_exists?('foo')).to eq(true)
    end

    it 'returns false if a branch does not exist' do
      rc = stubbed_rc

      expect(ReleaseTools::GitlabClient)
        .to receive(:find_branch)
        .with('foo', described_class::PROJECT)
        .and_return(nil)

      expect(rc.branch_exists?('foo')).to eq(false)
    end
  end

  describe '#create_source_branch' do
    context 'when there are deployments' do
      it 'creates the source branch from the last production deployment' do
        rc = stubbed_rc

        allow(ReleaseTools::GitlabClient)
          .to receive(:deployments)
          .with(described_class::PROJECT, described_class::PRODUCTION)
          .and_return([double(:deploy, iid: 1)])

        expect(ReleaseTools::GitlabClient)
          .to receive(:create_branch)
          .with(
            rc.source_branch,
            "refs/environments/#{described_class::PRODUCTION}/deployments/1",
            described_class::PROJECT
          )

        rc.create_source_branch
      end
    end

    context 'when there are no deployments' do
      it 'raises an error' do
        allow(ReleaseTools::GitlabClient)
          .to receive(:deployments)
          .with(described_class::PROJECT, described_class::PRODUCTION)
          .and_return([])

        expect { stubbed_rc.create_source_branch }.to raise_error(StandardError)
      end
    end
  end

  describe '#delete_source_branch' do
    it 'deletes the source branch' do
      rc = stubbed_rc

      expect(ReleaseTools::GitlabClient)
        .to receive(:delete_branch)
        .with(rc.source_branch, described_class::PROJECT)

      rc.delete_source_branch
    end
  end

  describe '#source_branch' do
    it 'returns the name of the current auto-deploy branch' do
      expect(stubbed_rc.source_branch).to match(/release-tools\/12\.9/)
    end
  end

  describe '#target_branch' do
    it 'returns the name of the stable branch to merge into' do
      expect(stubbed_rc.target_branch).to eq('12-9-stable-ee')
    end
  end
end
