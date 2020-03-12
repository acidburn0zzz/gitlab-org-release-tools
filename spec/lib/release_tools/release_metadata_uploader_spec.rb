# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::ReleaseMetadataUploader do
  describe '#upload' do
    let(:uploader) { described_class.new }
    let(:data) { ReleaseTools::ReleaseMetadata.new }
    let(:json) do
      JSON.pretty_generate(
        security: false,
        releases: {
          foo: {
            version: '1.2.3',
            sha: '123abc',
            ref: 'master',
            tag: false
          },
          bar: {
            version: '4.5.6',
            sha: '123abc',
            ref: 'master',
            tag: false
          }
        }
      )
    end

    before do
      data.add_release(
        name: 'foo',
        version: '1.2.3',
        sha: '123abc',
        ref: 'master',
        tag: false
      )

      data.add_release(
        name: 'bar',
        version: '4.5.6',
        sha: '123abc',
        ref: 'master',
        tag: false
      )
    end

    it 'uploads the release data' do
      expect(ReleaseTools::GitlabOpsClient)
        .to receive(:create_file)
        .with(
          described_class::PROJECT,
          'releases/cng/1/1.2.3.json',
          'master',
          json,
          'Add release data for 1.2.3'
        )

      uploader.upload('cng', '1.2.3', data)
    end

    it 'overwrites existing data when it already exists' do
      expect(ReleaseTools::GitlabOpsClient)
        .to receive(:create_file)
        .with(
          described_class::PROJECT,
          'releases/cng/1/1.2.3.json',
          'master',
          json,
          'Add release data for 1.2.3'
        )
        .and_raise(gitlab_error(:BadRequest))

      expect(ReleaseTools::GitlabOpsClient)
        .to receive(:edit_file)
        .with(
          described_class::PROJECT,
          'releases/cng/1/1.2.3.json',
          'master',
          json,
          'Add release data for 1.2.3'
        )

      uploader.upload('cng', '1.2.3', data)
    end
  end
end
