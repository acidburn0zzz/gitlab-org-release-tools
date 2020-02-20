# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::AutoDeploy::Naming do
  describe '.branch' do
    it 'returns a branch name in the appropriate format' do
      allow(ReleaseTools::GitlabClient).to receive(:current_milestone)
        .and_return(double(title: '4.2'))

      Timecop.travel(Date.new(2019, 7, 2)) do
        expect(described_class.branch).to eq('4-2-auto-deploy-20190702')
      end
    end
  end

  describe '.tag' do
    it 'returns a tag name in the appropriate format' do
      allow(ReleaseTools::GitlabClient).to receive(:current_milestone)
        .and_return(double(title: '4.2'))

      args = {
        timestamp: Time.new(2019, 7, 2, 10, 14).to_s,
        packager_ref: SecureRandom.hex(20),
        ee_ref: SecureRandom.hex(20)
      }

      expect(described_class.tag(**args)).to eq(
        "4.2.201907021014+#{args[:ee_ref][0...11]}.#{args[:packager_ref][0...11]}"
      )
    end
  end

  describe '#version' do
    it 'raises an error when the milestone format is unexpected' do
      allow(ReleaseTools::GitlabClient).to receive(:current_milestone)
        .and_return(double(title: 'Backlog'))

      expect { described_class.new.version }
        .to raise_error(/Invalid version from milestone/)
    end
  end
end
