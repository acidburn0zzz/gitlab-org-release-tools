# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::PassingBuild do
  let(:fake_commit) { double('Commit', id: SecureRandom.hex(20)) }
  let(:target_branch) { '11-10-auto-deploy-1234' }

  subject(:service) { described_class.new(target_branch) }

  describe '#execute' do
    let(:fake_commits) { spy }

    before do
      stub_const('ReleaseTools::Commits', fake_commits)
    end

    it 'raises an error without a dev commit' do
      expect(fake_commits).to receive(:latest_successful_on_build)
        .and_return(nil)

      expect { service.execute }
        .to raise_error(/Unable to find a passing/)
    end

    it 'returns the latest successful commit on Build' do
      expect(fake_commits).to receive(:latest_successful_on_build)
        .and_return(fake_commit)

      expect(service.execute).to eq(fake_commit)
    end
  end
end
