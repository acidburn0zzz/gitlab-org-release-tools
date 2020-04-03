# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::AutoDeploy::Tagger::Helm do
  let(:fake_client) { spy(project_path: described_class::PROJECT.path) }

  let(:target_branch) { '12-9-auto-deploy-20200226' }
  let(:version_map) do
    {
      'GITLAB_VERSION' => SecureRandom.hex(20),
      'GITALY_SERVER_VERSION' => SecureRandom.hex(20)
    }
  end
  let(:tag) { "12.9.202002281327+#{version_map['GITLAB_VERSION'].slice(0, 11)}" }

  subject(:tagger) { described_class.new(target_branch, version_map) }

  before do
    stub_const('ReleaseTools::GitlabClient', fake_client)
  end

  describe 'initialize' do
    it 'raises an error when unable to determine helm trigger token' do
      ClimateControl.modify(HELM_BUILD_TRIGGER_TOKEN: nil) do
        expect { subject }
          .to raise_error("Missing environment variable `HELM_BUILD_TRIGGER_TOKEN`")
      end
    end
  end

  describe '#tag!' do
    it 'triggers a build on the chart repository' do
      variables = {
        'AUTO_DEPLOY_TAG' => tag,
        'TRIGGER_JOB' => 'tag_auto_deploy',
        'AUTO_DEPLOY_COMPONENT_GITLAB_VERSION' => version_map['GITLAB_VERSION'],
        'AUTO_DEPLOY_COMPONENT_GITALY_SERVER_VERSION' => version_map['GITALY_SERVER_VERSION']
      }
      trigger_token = 'helm_token'

      without_dry_run do
        ClimateControl.modify(HELM_BUILD_TRIGGER_TOKEN: trigger_token) do
          tagger.tag!(tag)
        end
      end

      expect(fake_client).to have_received(:run_trigger)
        .with(described_class::PROJECT, trigger_token, target_branch, variables)
    end
  end
end
