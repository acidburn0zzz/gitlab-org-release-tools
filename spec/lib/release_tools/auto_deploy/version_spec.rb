# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::AutoDeploy::Version do
  let(:branch_name) { '12-1-auto-deploy-0012345' }

  describe '.from_branch' do
    it 'extracts version number from branch name' do
      version = described_class.from_branch(branch_name)

      expect(version.to_patch).to eq('12.1.0')
    end

    it 'assigns `stable_branch` attribute' do
      version = described_class.from_branch(branch_name)

      expect(version.stable_branch)
        .to be_instance_of(ReleaseTools::AutoDeployBranch)
      expect(version.stable_branch.branch_name)
        .to eq(branch_name)
    end

    context 'with a `security/` prefix' do
      it 'extracts version number from branch name' do
        branch_name = 'security/12-3-auto-deploy-20191015'

        version = described_class.from_branch(branch_name)

        expect(version.to_patch).to eq('12.3.0')
      end
    end
  end

  describe '#stable_branch=' do
    it 'converts the value to a String' do
      version = described_class.from_branch(branch_name)

      expect(version.stable_branch.branch_name)
        .to eq(branch_name)

      expect(version.stable_branch.version).to eq('12.1.0')

      version = version.to_ce

      expect(version.stable_branch.branch_name)
        .to eq(branch_name)
    end
  end

  describe '#to_ce' do
    it 'converts to CE and assigns branch' do
      version = described_class
        .from_branch(branch_name)
        .to_ce

      expect(version).not_to be_ee
      expect(version.stable_branch).not_to be_nil
    end
  end

  describe '#to_ee' do
    it 'converts to EE and assigns branch' do
      version = described_class
        .from_branch(branch_name)
        .to_ee

      expect(version).to be_ee
      expect(version.stable_branch).not_to be_nil
    end
  end
end
