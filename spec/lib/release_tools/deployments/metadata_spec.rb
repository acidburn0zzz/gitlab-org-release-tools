# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Deployments::Metadata do
  describe '#security_release?' do
    context 'when using an auto-deploy version' do
      it 'returns true when the version is a security release' do
        meta = described_class.new('12.7.202001101501-94b8fd8d152.6fea3031ec9')

        allow(ReleaseTools::GitlabClient)
          .to receive(:commit)
          .with(ReleaseTools::Project::OmnibusGitlab, ref: '6fea3031ec9')
          .and_raise(gitlab_error(:NotFound, code: 404))

        expect(meta).to be_security_release
      end

      it 'returns false when the version is a regular release' do
        meta = described_class.new('12.7.202001101501-94b8fd8d152.6fea3031ec9')

        allow(ReleaseTools::GitlabClient)
          .to receive(:commit)
          .with(ReleaseTools::Project::OmnibusGitlab, ref: '6fea3031ec9')
          .and_return(double(:commit))

        expect(meta).not_to be_security_release
      end
    end

    context 'when using a patch version' do
      it 'returns true when the version is a security release' do
        meta = described_class.new('12.5.0-rc43.ee.0')

        allow(ReleaseTools::GitlabClient)
          .to receive(:tag)
          .with(ReleaseTools::Project::OmnibusGitlab, tag: '12.5.0+rc43.ee.0')
          .and_raise(gitlab_error(:NotFound, code: 404))

        expect(meta).to be_security_release
      end

      it 'returns false when the version is a regular release' do
        meta = described_class.new('12.5.0-rc43.ee.0')

        allow(ReleaseTools::GitlabClient)
          .to receive(:tag)
          .with(ReleaseTools::Project::OmnibusGitlab, tag: '12.5.0+rc43.ee.0')
          .and_return(double(:tag))

        expect(meta).not_to be_security_release
      end
    end
  end
end
