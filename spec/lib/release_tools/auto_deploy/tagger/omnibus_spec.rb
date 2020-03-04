# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::AutoDeploy::Tagger::Omnibus do
  let(:fake_client) { spy(project_path: described_class::PROJECT.path) }
  let(:target_branch) { '12-9-auto-deploy-20200226' }
  let(:version_map) do
    {
      'VERSION' => SecureRandom.hex(20),
      'GITALY_SERVER_VERSION' => SecureRandom.hex(20)
    }
  end

  subject(:tagger) { described_class.new(target_branch, version_map) }

  before do
    stub_const('ReleaseTools::GitlabClient', fake_client)
  end

  describe '#tag_name' do
    it 'returns a tag name in the appropriate format' do
      commit = double(
        created_at: Time.new(2019, 7, 2, 10, 14),
        id: SecureRandom.hex(20)
      )

      allow(tagger).to receive(:branch_head).and_return(commit)

      expect(tagger.tag_name).to eq(
        "12.9.201907021014+#{version_map['VERSION'][0...11]}.#{commit.id[0...11]}"
      )
    end
  end

  describe '#tag_message' do
    it 'returns a formatted tag message' do
      allow(tagger).to receive(:tag_name).and_return('some_tag')

      expected = <<~MSG.chomp
        Auto-deploy Omnibus some_tag

        VERSION: #{version_map['VERSION']}
        GITALY_SERVER_VERSION: #{version_map['GITALY_SERVER_VERSION']}
      MSG

      expect(tagger.tag_message).to eq(expected)
    end
  end

  describe '#tag!' do
    it 'creates a tag on the project' do
      branch_head = double(
        created_at: Time.new(2019, 7, 2, 10, 14),
        id: SecureRandom.hex(20)
      )

      allow(tagger).to receive(:branch_head).and_return(branch_head)
      allow(tagger).to receive(:tag_name).and_return('tag_name')

      without_dry_run do
        tagger.tag!
      end

      expect(fake_client).to have_received(:create_tag)
        .with(described_class::PROJECT.path, 'tag_name', branch_head.id, anything)
    end
  end
end
