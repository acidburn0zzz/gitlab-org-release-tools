# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::ClientWrapper do
  describe '#method_missing' do
    let(:fake_client) { spy }

    subject(:wrapper) { described_class.new(fake_client) }

    it 'sends certain methods through directly' do
      method = described_class::SKIP_METHODS.sample
      args = %w[arg1 arg2]
      block = -> {}

      expect(wrapper).not_to receive(:logger)
      expect(fake_client).to receive(:send).with(method, args, block)

      wrapper.send(method, args, block)
    end

    it 'translates Project objects to paths based on context' do
      project = double(
        dev_path: 'dev/project',
        ops_path: 'ops/project',
        security_path: 'security/project',
        path: 'production/project'
      )

      dev  = spy(endpoint: described_class::DEV_ENDPOINT)
      ops  = spy(endpoint: described_class::OPS_ENDPOINT)
      prod = spy(endpoint: described_class::PRODUCTION_ENDPOINT)
      security = spy(endpoint: described_class::PRODUCTION_ENDPOINT)

      described_class.new(dev).project(project)
      described_class.new(ops).project(project)
      described_class.new(prod).project(project)
      ClimateControl.modify(SECURITY: 'true') do
        described_class.new(security).project(project)
      end

      expect(dev).to have_received(:project).with(project.dev_path)
      expect(ops).to have_received(:project).with(project.ops_path)
      expect(prod).to have_received(:project).with(project.path)
      expect(security).to have_received(:project).with(project.security_path)
    end

    it 'logs API errors' do
      expect(fake_client).to receive(:file_contents)
        .and_raise(gitlab_error(:NotFound, code: 404))

      logger = spy
      allow(wrapper).to receive(:logger).and_return(logger)

      expect { wrapper.file_contents('foo', 'bar') }
        .to raise_error(Gitlab::Error::NotFound)

      expect(logger)
        .to have_received(:warn)
        .with(
          'GitLab API error',
          hash_including(method: :file_contents, args: %w[foo bar])
        )
    end
  end
end
