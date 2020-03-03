# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::SharedStatus do
  describe '.dry_run?' do
    it 'returns true when set' do
      ClimateControl.modify(TEST: 'true') do
        expect(described_class.dry_run?).to eq(true)
      end
    end

    it 'returns false when unset' do
      ClimateControl.modify(TEST: nil) do
        expect(described_class.dry_run?).to eq(false)
      end
    end
  end

  describe '.security_release?' do
    it 'returns true when set' do
      ClimateControl.modify(SECURITY: 'true') do
        expect(described_class.security_release?).to eq(true)
      end
    end

    it 'returns false when unset' do
      ClimateControl.modify(SECURITY: nil) do
        expect(described_class.security_release?).to eq(false)
      end
    end
  end

  describe '#as_security_release' do
    it 'allows enabling of security releases for the duration of the block' do
      described_class.as_security_release do
        expect(described_class.security_release?).to eq(true)
      end

      expect(described_class.security_release?).to eq(false)
    end
  end
end
