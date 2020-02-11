# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Release::CNGImageRelease do
  required_opts = { gitlab_repo_path: '/tmp' }

  describe '#version_string_from_gemfile' do
    context 'when the Gemfile.lock file does not exist' do
      let(:opts) { { gitlab_repo_path: '' } }
      let(:release) { described_class.new('1.1.1', opts) }

      it 'raises a VersionFileDoesNotExistError' do
        expect do
          release.version_string_from_gemfile('mail_room')
        end.to raise_error(described_class::VersionFileDoesNotExistError)
      end
    end

    context 'when the Gemfile.lock contains the version we are looking for' do
      let(:fixture) { VersionFixture.new }
      let(:opts) { { gitlab_repo_path: fixture.fixture_path } }
      let(:release) { described_class.new('1.1.1', opts) }

      it 'returns the version' do
        expect do
          release.version_string_from_gemfile('mail_room')
        end.not_to raise_error

        expect(
          release.version_string_from_gemfile('mail_room')
        ).to eq('0.9.1')
      end
    end

    context 'when the Gemfile.lock does not contain the version we are looking for' do
      let(:fixture) { VersionFixture.new }
      let(:opts) { { gitlab_repo_path: fixture.fixture_path } }
      let(:release) { described_class.new('1.1.1', opts) }

      it 'raises a VersionNotFoundError' do
        expect do
          release.version_string_from_gemfile('foobar')
        end.to raise_error(described_class::VersionNotFoundError)
      end
    end
  end

  describe '#tag' do
    context 'when CE and UBI is enabled' do
      let(:opts) { { ubi: true }.merge(required_opts) }
      let(:release) { described_class.new('1.1.1', opts) }

      it 'returns the CE tag' do
        expect(release.tag).to eq 'v1.1.1'
      end
    end

    context 'when EE and UBI is disabled' do
      let(:opts) { { ubi: false }.merge(required_opts) }
      let(:release) { described_class.new('1.1.1-ee', opts) }

      it 'returns the EE tag' do
        expect(release.tag).to eq 'v1.1.1-ee'
      end
    end

    context 'when EE and UBI is enabled' do
      let(:opts) { { ubi: true }.merge(required_opts) }
      let(:release) { described_class.new('1.1.1-ee', opts) }

      it 'returns the UBI tag' do
        expect(release.tag).to eq 'v1.1.1-ubi8'
      end
    end

    context 'when EE and UBI is enabled and UBI version is specified' do
      let(:opts) { { ubi: true, ubi_version: '7' }.merge(required_opts) }
      let(:release) { described_class.new('1.1.1-ee', opts) }

      it 'returns the specified UBI tag' do
        expect(release.tag).to eq 'v1.1.1-ubi7'
      end
    end
  end
end
