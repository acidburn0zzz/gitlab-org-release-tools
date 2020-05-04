# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::AutoDeployBranch do
  let(:branch) { described_class.new('12-9-auto-deploy-20200226') }

  describe '.current_name' do
    context 'when the AUTO_DEPLOY_BRANCH variable is not set' do
      it 'raises KeyError' do
        ClimateControl.modify(AUTO_DEPLOY_BRANCH: nil) do
          expect { described_class.current_name }.to raise_error(KeyError)
        end
      end
    end

    context 'when the AUTO_DEPLOY_BRANCH variable is set' do
      it 'returns the value of the variable' do
        ClimateControl.modify(AUTO_DEPLOY_BRANCH: 'foo') do
          expect(described_class.current_name).to eq('foo')
        end
      end
    end
  end

  describe '.current' do
    it 'returns an AutoDeployBranch for the current auto-deploy branch' do
      branch_name = '12-9-auto-deploy-20200226'
      branch = ClimateControl.modify(AUTO_DEPLOY_BRANCH: branch_name) do
        described_class.current
      end

      expect(branch.version.to_s).to eq('12.9.0')
      expect(branch.to_s).to eq(branch_name)
    end
  end

  describe '#exists?' do
    it 'returns true' do
      expect(branch.exists?).to eq(true)
    end
  end

  describe '#pick_destination' do
    it 'returns the branch name as a Markdown code block' do
      expect(branch.pick_destination).to eq("`#{branch}`")
    end
  end

  describe '#release_issue' do
    it 'returns a release issue for the auto-deploy version' do
      issue = branch.release_issue

      expect(issue.version).to eq(branch.version)
    end
  end

  describe '#tag_timestamp' do
    it 'returns a timestamp to use for tags' do
      # We don't really care about the exact value, as long as it is always the
      # same for the same AutoDeployBranch instance.
      expect(branch.tag_timestamp).to eq(branch.tag_timestamp)
    end
  end
end
