# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::AutoDeploy::Tagger::CNGImage do
  let(:fake_client) { spy(project_path: described_class::PROJECT.path) }

  let(:target_branch) do
    ReleaseTools::AutoDeployBranch.new('12-9-auto-deploy-20200226')
  end

  let(:version_map) do
    {
      'GITLAB_VERSION' => SecureRandom.hex(20),
      'GITALY_SERVER_VERSION' => SecureRandom.hex(20)
    }
  end

  subject(:tagger) { described_class.new(target_branch, version_map) }

  before do
    stub_const('ReleaseTools::GitlabClient', fake_client)
    enable_feature(:release_json_tracking)
  end

  describe '#tag_name' do
    it 'returns a tag name in the appropriate format' do
      expect(tagger.tag_name).to eq(
        "12.9.#{target_branch.tag_timestamp}+#{version_map['GITLAB_VERSION'][0...11]}"
      )
    end
  end

  describe '#tag_message' do
    it 'returns a formatted tag message' do
      allow(tagger).to receive(:tag_name).and_return('some_tag')

      expected = <<~MSG.chomp
        Auto-deploy CNG some_tag

        GITLAB_VERSION: #{version_map['GITLAB_VERSION']}
        GITALY_SERVER_VERSION: #{version_map['GITALY_SERVER_VERSION']}
      MSG

      expect(tagger.tag_message).to eq(expected)
    end
  end

  describe '#tag!' do
    context 'without changes' do
      before do
        allow(tagger).to receive(:changes?).and_return(false)
      end

      it 'does nothing' do
        expect(fake_client).not_to receive(:create_tag)

        without_dry_run do
          tagger.tag!
        end
      end
    end

    context 'with changes' do
      let(:fake_helm_tagger) { spy('helm_tagger') }

      before do
        allow(ReleaseTools::AutoDeploy::Tagger::Helm).to receive(:new).and_return(fake_helm_tagger)
        allow(tagger).to receive(:changes?).and_return(true)
      end

      it 'creates a tag on the project' do
        branch_head = double(
          created_at: Time.new(2019, 7, 2, 10, 14),
          id: SecureRandom.hex(20)
        )

        allow(tagger).to receive(:branch_head).and_return(branch_head)
        allow(tagger).to receive(:tag_name).and_return('tag_name')
        allow(tagger).to receive(:upload_version_data).with('cng')

        without_dry_run do
          tagger.tag!
        end

        expect(fake_client).to have_received(:create_tag)
          .with(described_class::PROJECT.path, 'tag_name', branch_head.id, anything)
        expect(fake_helm_tagger).to have_received(:tag!).with('tag_name')
      end

      it 'uses the dev client in a security release' do
        fake_dev_client = stub_const('ReleaseTools::GitlabDevClient', spy)

        allow(tagger).to receive(:branch_head).and_return(spy)
        allow(tagger).to receive(:tag_name).and_return('tag_name')
        allow(tagger).to receive(:upload_version_data).with('cng')
        allow(ReleaseTools::SharedStatus).to receive(:security_release?)
          .and_return(true)

        without_dry_run do
          tagger.tag!
        end

        expect(fake_dev_client).to have_received(:create_tag)
        expect(fake_client).not_to have_received(:create_tag)
      end

      it 'uploads the version data' do
        branch_head = double(
          created_at: Time.new(2019, 7, 2, 10, 14),
          id: 'foo'
        )

        uploader = instance_spy(ReleaseTools::ReleaseMetadataUploader)

        allow(tagger).to receive(:branch_head).and_return(branch_head)
        allow(tagger).to receive(:tag_name).and_return('12.1.3')

        allow(ReleaseTools::ReleaseMetadataUploader)
          .to receive(:new)
          .and_return(uploader)

        expect(uploader)
          .to receive(:upload)
          .with('cng', '12.1.3', an_instance_of(ReleaseTools::ReleaseMetadata))

        without_dry_run do
          tagger.tag!
        end
      end
    end
  end
end
