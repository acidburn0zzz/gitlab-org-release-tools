# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::AutoDeploy::Builder::Omnibus do
  let(:fake_commit) { double('Commit', id: SecureRandom.hex(20)) }
  let(:target_branch) { '11-10-auto-deploy-1234' }
  let(:version_map) { { 'VERSION' => '1.2.3' } }

  describe '#execute' do
    let!(:component_versions) do
      stub_const('ReleaseTools::ComponentVersions', spy)
    end

    let!(:tagger) do
      stub_const('ReleaseTools::AutoDeploy::Tagger::Omnibus', spy)
    end

    it 'updates component versions and tags' do
      expect(component_versions)
        .to receive(:get_omnibus_compat_versions)
        .with(fake_commit.id)
        .and_return(version_map)

      expect(component_versions)
        .to receive(:update_omnibus)
        .with(target_branch, version_map)

      expect(tagger)
        .to receive(:new)
        .with(target_branch, version_map, an_instance_of(ReleaseTools::ReleaseMetadata))

      expect(tagger).to receive(:tag!)

      builder = described_class.new(target_branch, fake_commit.id)
      builder.execute
    end
  end
end
