# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Deployments::ReleasedMergeRequestNotifier do
  describe '#notify' do
    let(:deploy) do
      ReleaseTools::Deployments::DeploymentTracker::Deployment
        .new(ReleaseTools::Project::GitlabEe, 1, 'success')
    end

    let(:version) { '12.5.0.ee.0' }

    it 'notifes the deployed merge requests' do
      updater = instance_spy(ReleaseTools::Deployments::MergeRequestUpdater)

      allow(ReleaseTools::Deployments::MergeRequestUpdater)
        .to receive(:for_successful_deployments)
        .with([deploy])
        .and_return(updater)

      allow(updater)
        .to receive(:add_comment)
        .with(/12.5.0 release.+\/label ~published/m)

      described_class.notify('pre', [deploy], version)

      expect(updater).to have_received(:add_comment)
    end

    it 'notifies merge requests when deploying an RC' do
      updater = instance_spy(ReleaseTools::Deployments::MergeRequestUpdater)

      allow(ReleaseTools::Deployments::MergeRequestUpdater)
        .to receive(:for_successful_deployments)
        .with([deploy])
        .and_return(updater)

      allow(updater)
        .to receive(:add_comment)
        .with(/12.5.0 release.+\/label ~published/m)

      described_class.notify('pre', [deploy], '12.5.0-rc43.ee.0')

      expect(updater).to have_received(:add_comment)
    end

    it 'does not notify merge request when deploying to staging' do
      expect(ReleaseTools::Deployments::MergeRequestUpdater)
        .not_to receive(:for_successful_deployments)

      described_class.notify('gstg', [deploy], version)
    end

    it 'does not notify merge request when deploying to production' do
      expect(ReleaseTools::Deployments::MergeRequestUpdater)
        .not_to receive(:for_successful_deployments)

      described_class.notify('gprd', [deploy], version)
    end

    it 'does not notify merge request when deploying to canary' do
      expect(ReleaseTools::Deployments::MergeRequestUpdater)
        .not_to receive(:for_successful_deployments)

      described_class.notify('gprd-cny', [deploy], version)
    end

    it 'does not notify merge requests when deploying an unsupported version' do
      expect(ReleaseTools::Deployments::MergeRequestUpdater)
        .not_to receive(:for_successful_deployments)

      described_class.notify('pre', [deploy], '12.5.0.4.5.6.ee.0')
    end
  end
end
