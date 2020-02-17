# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Deployments::MergeRequestLabeler do
  let(:labeler) { described_class.new }

  describe '#label_merge_requests' do
    context 'when deploying to an environment without a workflow label' do
      it 'does not update any merge requests' do
        deploy = ReleaseTools::Deployments::DeploymentTracker::Deployment
          .new(ReleaseTools::Project::GitlabEe, 1, 'success')

        expect(ReleaseTools::Deployments::MergeRequestUpdater)
          .not_to receive(:for_successful_deployments)

        labeler.label_merge_requests('kittens', [deploy])
      end
    end

    context 'when deploying to an environment with a workflow label' do
      it 'adds the workflow label to all merge requests' do
        deploy = ReleaseTools::Deployments::DeploymentTracker::Deployment
          .new(ReleaseTools::Project::GitlabEe, 1, 'success')

        merge_request =
          double(:mr, project_id: 2, iid: 3, labels: %w[foo], web_url: 'foo')

        page = Gitlab::PaginatedResponse.new([merge_request])

        allow(ReleaseTools::GitlabClient)
          .to receive(:deployed_merge_requests)
          .with(ReleaseTools::Project::GitlabEe, 1)
          .and_return(page)

        expect(ReleaseTools::GitlabClient)
          .to receive(:update_merge_request)
          .with(2, 3, labels: 'workflow::staging,foo')

        labeler.label_merge_requests('gstg', [deploy])
      end

      it 'skips deployments that did not succeed' do
        deploy = ReleaseTools::Deployments::DeploymentTracker::Deployment
          .new(ReleaseTools::Project::GitlabEe, 1, 'failed')

        expect(ReleaseTools::GitlabClient)
          .not_to receive(:create_merge_request_comment)

        labeler.label_merge_requests('gstg', [deploy])
      end
    end
  end
end
