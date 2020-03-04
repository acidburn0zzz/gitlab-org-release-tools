# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Security::Pipeline do
  describe '.latest_for_merge_request' do
    context 'when the merge request has a pipeline attached' do
      let(:merge_request) do
        double(:merge_request, pipeline: double(:pipeline), project_id: 1)
      end

      let(:client) { instance_spy(ReleaseTools::Security::Client) }

      before do
        allow(client).to receive(:latest_merge_request_pipeline)
      end

      it 'returns a Pipeline' do
        pipeline = described_class
          .latest_for_merge_request(merge_request, client)

        expect(pipeline).to be_an_instance_of(described_class)
      end

      it 'does not request the latest merge request using the API' do
        described_class.latest_for_merge_request(merge_request, client)

        expect(client).not_to have_received(:latest_merge_request_pipeline)
      end
    end

    context 'when the merge request does not have a pipeline attached' do
      let(:merge_request) do
        double(:merge_request, pipeline: nil, project_id: 1, iid: 2)
      end

      let(:client) { instance_spy(ReleaseTools::Security::Client) }

      before do
        allow(client)
          .to receive(:latest_merge_request_pipeline)
          .with(1, 2)
          .and_return(double(:pipeline))
      end

      it 'returns a Pipeline' do
        pipeline = described_class
          .latest_for_merge_request(merge_request, client)

        expect(pipeline).to be_an_instance_of(described_class)
      end

      it 'requests the latest merge request pipeline using the API' do
        described_class.latest_for_merge_request(merge_request, client)

        expect(client).to have_received(:latest_merge_request_pipeline)
      end
    end

    context 'when no pipeline could be found' do
      it 'returns nil' do
        merge_request =
          double(:merge_request, pipeline: nil, project_id: 1, iid: 2)

        client = instance_spy(ReleaseTools::Security::Client)

        allow(client).to receive(:latest_merge_request_pipeline)

        pipeline = described_class
          .latest_for_merge_request(merge_request, client)

        expect(pipeline).to be_nil
      end
    end
  end

  describe '#passed?' do
    it 'returns true when the pipeline passed' do
      pipeline = described_class
        .new(double(:client), 1, double(:pipeline, status: 'success'))

      expect(pipeline).to be_passed
    end

    it 'returns false when the pipeline did not pass' do
      pipeline = described_class
        .new(double(:client), 1, double(:pipeline, status: 'failed'))

      expect(pipeline).not_to be_passed
    end
  end

  describe '#pending?' do
    it 'returns false when the pipeline failed' do
      pipeline = described_class
        .new(double(:client), 1, double(:pipeline, status: 'failed'))

      expect(pipeline).not_to be_pending
    end

    it 'returns false when the pipeline passed' do
      pipeline = described_class
        .new(double(:client), 1, double(:pipeline, status: 'success'))

      expect(pipeline).not_to be_pending
    end

    it 'returns true when the pipeline is pending' do
      pipeline = described_class
        .new(double(:client), 1, double(:pipeline, status: 'pending'))

      expect(pipeline).to be_pending
    end
  end

  describe '#failed?' do
    it 'returns false if the pipeline did not fail' do
      pipeline = described_class
        .new(double(:client), 1, double(:pipeline, status: 'success'))

      expect(pipeline).not_to be_failed
    end

    it 'returns false if a job failed that is allowed to fail' do
      pipeline = described_class
        .new(double(:client), 1, double(:pipeline, status: 'failed'))

      allow(pipeline)
        .to receive(:allowed_failures)
        .and_return(Set.new(%w[rspec-1]))

      allow(pipeline)
        .to receive(:latest_jobs)
        .and_return([double(:job, name: 'rspec-1', status: 'failed')])

      expect(pipeline).not_to be_failed
    end

    it 'returns true if a job failed that is not allowed to fail' do
      pipeline = described_class
        .new(double(:client), 1, double(:pipeline, status: 'failed'))

      allow(pipeline)
        .to receive(:allowed_failures)
        .and_return(Set.new(%w[]))

      allow(pipeline)
        .to receive(:latest_jobs)
        .and_return([double(:job, name: 'downtime_check', status: 'failed')])

      expect(pipeline).to be_failed
    end
  end

  describe '#allowed_failures' do
    it 'returns the names of the builds that are allowed to fail' do
      client = double(:client)
      pipeline = described_class.new(client, 1, double(:pipeline, sha: '123'))

      job1 = double(:job, allow_failure: false, name: 'foo')
      job2 = double(:job, allow_failure: true, name: 'bar')
      jobs = double(:jobs, auto_paginate: [job1, job2])

      allow(client)
        .to receive(:commit_status)
        .with(1, '123', per_page: 100)
        .and_return(jobs)

      expect(pipeline.allowed_failures).to eq(Set.new(%w[bar]))
    end
  end

  describe '#latest_jobs' do
    it 'returns an Array containing the latest pipeline jobs' do
      client = double(:client)
      pipeline = described_class.new(client, 2, double(:pipeline, id: 1))

      job1 = double(:job, id: 1, name: 'foo')
      job2 = double(:job, id: 2, name: 'foo')
      job3 = double(:job, id: 3, name: 'bar')
      jobs = double(:jobs, auto_paginate: [job1, job2, job3])

      allow(client)
        .to receive(:pipeline_jobs)
        .with(2, 1, per_page: 100)
        .and_return(jobs)

      latest = pipeline.latest_jobs

      expect(latest).to contain_exactly(job2, job3)
    end
  end
end
