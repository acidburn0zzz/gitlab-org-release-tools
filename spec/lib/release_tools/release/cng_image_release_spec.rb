# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Release::CNGImageRelease do
  required_opts = { gitlab_repo_path: '/tmp' }

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

  describe '#component_versions' do
    def component_versions(version)
      fixture = ReleaseFixture.new
      fixture.rebuild_fixture!

      release = described_class.new(version, gitlab_repo_path: fixture.repository.workdir)

      release.__send__(:component_versions)
    end

    it 'finds all the component versions' do
      version = '1.1.1-ee'

      expect(component_versions(version)).to include(
        'GITLAB_ASSETS_TAG' => "v#{version}",
        'GITLAB_REF_SLUG' => "v#{version}",
        'GITLAB_VERSION' => "v#{version}",
        'MAILROOM_VERSION' => '0.0.3',
        'GITALY_SERVER_VERSION' => 'v5.6.0',
        'GITLAB_ELASTICSEARCH_INDEXER_VERSION' => 'v9.9.9',
        'GITLAB_SHELL_VERSION' => 'v2.3.0',
        'GITLAB_WORKHORSE_VERSION' => 'v3.4.0'
      )
    end
  end
end
