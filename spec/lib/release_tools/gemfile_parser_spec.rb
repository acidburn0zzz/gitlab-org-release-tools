# frozen_string_literal: true

require 'spec_helper'
require 'pry'

describe ReleaseTools::GemfileParser do
  context 'with non-existent file' do
    it 'raises a LockfileNotFoundError' do
      expect { described_class.new('/foobar.lock') }
        .to raise_error(described_class::LockfileNotFoundError)
    end
  end

  describe '#gem_version' do
    let(:fixture) { VersionFixture.new }
    let(:lockfile) { "#{fixture.fixture_path}/Gemfile.lock" }

    subject(:parser) { described_class.new(lockfile) }

    it 'returns the version for a known dependency' do
      expect(parser.gem_version('mail_room')).to eq('0.9.1')
    end

    it 'raises `VersionNotFoundError` for an unknown dependency' do
      expect { parser.gem_version('foobar') }
        .to raise_error(described_class::VersionNotFoundError)
    end
  end
end
