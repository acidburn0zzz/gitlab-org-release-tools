# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Deployments::OmnibusDeploymentVersionParser do
  describe '#parse' do
    context 'when parsing an invalid version' do
      it 'raises ArgumentError' do
        expect { described_class.new.parse('foo') }
          .to raise_error(ArgumentError)
      end
    end

    context 'when parsing an auto-deploy version without pipelines' do
      it 'returns a version for the master branch' do
        allow(ReleaseTools::GitlabClient)
          .to receive(:pipelines)
          .and_return([])

        allow(ReleaseTools::GitlabClient)
          .to receive(:commit)
          .and_return(
            double(:commit, id: '6fea3031ec9772066c7abc60d81541f9abd13577')
          )

        version =
          described_class.new.parse('12.7.202001101501-94b8fd8d152.6fea3031ec9')

        expect(version.ref).to eq('master')
        expect(version.sha).to eq('6fea3031ec9772066c7abc60d81541f9abd13577')
        expect(version.tag?).to eq(false)
      end
    end

    context 'when parsing an auto-deploy version with pipelines' do
      it 'returns a version for the auto-deploy branch' do
        pipeline1 = double(:pipeline, ref: 'foo')
        pipeline2 = double(:pipeline, ref: '1-2-auto-deploy-12345678')
        pipeline3 = double(:pipeline, ref: '1-2-auto-deploy-45678901')

        allow(ReleaseTools::GitlabClient)
          .to receive(:pipelines)
          .and_return([pipeline1, pipeline2, pipeline3])

        allow(ReleaseTools::GitlabClient)
          .to receive(:commit)
          .and_return(
            double(:commit, id: '6fea3031ec9772066c7abc60d81541f9abd13577')
          )

        version =
          described_class.new.parse('12.7.202001101501-94b8fd8d152.6fea3031ec9')

        expect(version.ref).to eq('1-2-auto-deploy-12345678')
        expect(version.sha).to eq('6fea3031ec9772066c7abc60d81541f9abd13577')
        expect(version.tag?).to eq(false)
      end
    end

    context 'when parsing a deployed tag' do
      it 'returns a DeploymentVersion' do
        allow(ReleaseTools::GitlabClient)
          .to receive(:tag)
          .and_return(
            double(
              :tag,
              commit: double(
                :commit,
                id: '38ff973f4a25f89fef28ee1a2cdd9d2c0144d274'
              ),
              name: '12.5.0+rc43.ee.0'
            )
          )

        version = described_class.new.parse('12.5.0-rc43.ee.0')

        expect(version.ref).to eq('12.5.0+rc43.ee.0')
        expect(version.sha).to eq('38ff973f4a25f89fef28ee1a2cdd9d2c0144d274')
        expect(version.tag?).to eq(true)
      end
    end

    context 'when parsing a deployed tag that does not exist' do
      it 'raises ArgumentError' do
        allow(ReleaseTools::GitlabClient)
          .to receive(:tag)
          .and_raise(gitlab_error(:NotFound))

        expect { described_class.new.parse('12.5.0-rc43.ee.0') }
          .to raise_error(ArgumentError)
      end
    end
  end
end
