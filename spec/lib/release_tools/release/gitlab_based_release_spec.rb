# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Release::GitlabBasedRelease do
  describe '.new' do
    let(:version) { '1.0.0' }
    let(:options) { { gitlab_repo_path: Dir.tmpdir } }

    subject { described_class.new(version, options) }

    it 'does not raise errors' do
      expect { subject }.not_to raise_error
    end

    context 'when the options hash has no gitlab_repo_path' do
      let(:options) { {} }

      it 'does raise an error' do
        expect { subject }.to raise_error ArgumentError, "missing gitlab_repo_path"
      end
    end
  end

  describe '#version_string' do
    let(:release) { described_class.new('1.0.0', gitlab_repo_path: Dir.tmpdir) }

    def version_string(version)
      release.version_string(version)
    end

    it 'prepends v on semver tags' do
      expect(version_string('1.1.1')).to eq('v1.1.1')
      expect(version_string('1.1.1-rc1')).to eq('v1.1.1-rc1')
      expect(version_string('1.1.1-ee')).to eq('v1.1.1-ee')
    end

    it 'return the input if does not match semver' do
      expect(version_string('eca3fba67cd40a0a09aa7b53260e180a402fa2bb')).to eq('eca3fba67cd40a0a09aa7b53260e180a402fa2bb')
      expect(version_string('master')).to eq('master')
      expect(version_string('feature-a')).to eq('feature-a')
    end
  end
end
