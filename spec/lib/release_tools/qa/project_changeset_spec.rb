# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Qa::ProjectChangeset, vcr: { cassette_name: 'commits-api' } do
  let(:project) { ReleaseTools::Project::GitlabCe }
  let(:from_ref) { 'v10.8.0-rc1' }
  let(:to_ref) { 'v10.8.0-rc2' }

  subject { described_class.new(project: project, from: from_ref, to: to_ref) }

  describe 'validations' do
    let(:from_ref) { 'invalid' }

    it 'raises an argument error for an invalid ref' do
      expect do
        subject
      end.to raise_error(ArgumentError)
    end
  end

  describe '#shas', vcr: { cassette_name: 'repository-api-compare' } do
    it 'has the correct shas' do
      shas = subject.shas

      expect(shas).to be_a(Array)
      expect(shas.size).to eq(3)
      expect(shas).to include('7f7153301ad59d864791cb85d8abd1135962e954')
    end
  end

  describe '#commits', vcr: { cassette_name: 'repository-api-compare' } do
    it 'downloads the list of commits from the API' do
      commits = subject.commits
      shas = commits.map { |c| c['id'] }

      expect(commits).to be_a(Array)
      expect(commits.size).to eq(3)
      expect(shas).to include('7f7153301ad59d864791cb85d8abd1135962e954')
    end

    context 'when default_client is specified' do
      let(:default_client) { ReleaseTools::GitlabDevClient }

      subject { described_class.new(project: project, from: from_ref, to: to_ref, default_client: default_client) }

      it 'uses the default_client instead of GitlabClient' do
        expect(default_client).to receive(:commit).with(project, ref: from_ref)
        expect(default_client).to receive(:commit).with(project, ref: to_ref)
        expect(default_client).to receive(:compare).with(project, from: from_ref, to: to_ref).and_return(double(commits: []))

        expect(subject.commits).to eq([])
      end
    end
  end

  describe '#merge_requests', vcr: { cassette_name: ['repository-api-compare', 'merge-requests-api'] } do
    it 'downloads the list of Merge Requests' do
      mrs = subject.merge_requests

      expect(mrs).to be_a(Array)
      expect(mrs.size).to eq(2)
      expect(mrs[0].iid).to eq(18_745)
      expect(mrs[1].iid).to eq(18_744)
    end

    it 'retries retrieving of a merge request when this times out' do
      raised = false

      allow(subject.default_client).to receive(:merge_request) do
        if raised
          raised = true
          raise Errno::ETIMEDOUT
        else
          double(:merge_request)
        end
      end

      expect(subject.merge_requests.size).to eq(2)
    end

    context 'for MRs created on another instance' do
      let(:from_ref) { 'v10.8.1' }
      let(:to_ref) { 'v10.8.2' }

      it 'downloads the list of merge requests' do
        mrs = subject.merge_requests

        expect(mrs).to be_a(Array)
        expect(mrs.size).to eq(3)
        expect(mrs[0].iid).to eq(2_388)
        expect(mrs[1].iid).to eq(2_387)
        expect(mrs[2].iid).to eq(2_390)
      end
    end
  end
end
