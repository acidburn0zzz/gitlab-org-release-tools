# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Preflight do
  describe '.check_mirroring' do
    around do |ex|
      # These checks only apply to CI
      ClimateControl.modify('CI' => 'true') do
        ex.run
      end
    end

    it 'does nothing outside ops' do
      ClimateControl.modify('CI_JOB_URL' => 'https://gitlab.com/gitlab-org/release-tools/-/jobs/460945779') do
        expect(described_class.check_mirroring).to eq(true)
      end
    end

    it 'logs a fatal message if any release-tools mirror has an error' do
      logger = spy
      allow(described_class).to receive(:logger).and_return(logger)

      expect(ReleaseTools::GitlabClient).to receive(:remote_mirrors)
        .and_return([double(last_error: nil), double(last_error: 'Error', url: 'url')])

      ClimateControl.modify('CI_JOB_URL' => 'https://ops.gitlab.net/gitlab-org/release/tools/-/jobs/964119') do
        described_class.check_mirroring
      end

      expect(logger).to have_received(:fatal)
        .with(anything, hash_including(mirror: 'url', error: 'Error'))
    end

    it 'logs a warning if the API returned an error' do
      logger = spy
      allow(described_class).to receive(:logger).and_return(logger)

      expect(ReleaseTools::GitlabClient).to receive(:remote_mirrors)
        .and_raise(gitlab_error(:BadRequest))

      ClimateControl.modify('CI_JOB_URL' => 'https://ops.gitlab.net/gitlab-org/release/tools/-/jobs/964119') do
        described_class.check_mirroring
      end

      expect(logger).to have_received(:warn)
        .with('Unable to determine mirror status', anything)
    end
  end
end
