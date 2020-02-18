# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Services::ComponentUpdateService do
  let(:internal_client) { double('ReleaseTools::GitlabClient') }
  let(:last_pages_commit)     { 'abc123f' }
  let(:last_workhorse_commit) { 'bbc123f' }
  let(:last_shell_commit)     { 'cbc123f' }
  let(:last_gitaly_commit)    { 'dbc123f' }
  let(:last_indexer_commit)   { 'ebc123f' }
  let(:target_branch) { 'test-auto-deploy-001' }
  let(:component_versions) do
    {
      'GITALY_SERVER_VERSION' => 'v4',
      'GITLAB_ELASTICSEARCH_INDEXER_VERSION' => 'v5',
      'GITLAB_PAGES_VERSION' => 'v1',
      'GITLAB_SHELL_VERSION' => 'v3',
      'GITLAB_WORKHORSE_VERSION' => 'v2'
    }
  end

  subject(:service) { described_class.new(target_branch) }

  before do
    enable_all_features
    allow(service).to receive(:gitlab_client).and_return(internal_client)
    allow(ReleaseTools::ComponentVersions).to receive(:get_omnibus_compat_versions)
      .with(ReleaseTools::Project::GitlabEe, target_branch)
      .and_return(component_versions)
  end

  describe '#execute' do
    it 'updates component versions' do
      expect(service).to receive(:latest_successful_ref)
                           .with(ReleaseTools::Project::GitlabPages)
                           .and_return(last_pages_commit)
                           .once
      expect(service).to receive(:latest_successful_ref)
                           .with(ReleaseTools::Project::GitlabShell)
                           .and_return(last_shell_commit)
                           .once
      expect(service).to receive(:latest_successful_ref)
                           .with(ReleaseTools::Project::Gitaly)
                           .and_return(last_gitaly_commit)
                           .once
      expect(service).to receive(:latest_successful_ref)
                           .with(ReleaseTools::Project::GitlabWorkhorse)
                           .and_return(last_workhorse_commit)
                           .once
      expect(service).to receive(:latest_successful_ref)
                           .with(ReleaseTools::Project::GitlabElasticsearchIndexer)
                           .and_return(last_indexer_commit)
                           .once
      expect(internal_client).to receive(:project_path)
                                   .with(ReleaseTools::Project::GitlabEe)
                                   .and_return('a project path')
      expect(internal_client).to receive(:create_commit).with(
        'a project path',
        target_branch,
        'Update component versions',
        match_array([
          { action: 'update', file_path: '/GITLAB_PAGES_VERSION', content: "#{last_pages_commit}\n" },
          { action: 'update', file_path: '/GITLAB_WORKHORSE_VERSION', content: "#{last_workhorse_commit}\n" },
          { action: 'update', file_path: '/GITALY_SERVER_VERSION', content: "#{last_gitaly_commit}\n" },
          { action: 'update', file_path: '/GITLAB_SHELL_VERSION', content: "#{last_shell_commit}\n" },
          { action: 'update', file_path: '/GITLAB_ELASTICSEARCH_INDEXER_VERSION', content: "#{last_indexer_commit}\n" }
        ])
      )

      without_dry_run do
        service.execute
      end
    end

    context 'when no component changed' do
      it 'does not update component versions' do
        expect(service).to receive(:latest_successful_ref)
                             .with(ReleaseTools::Project::GitlabPages)
                             .and_return(component_versions['GITLAB_PAGES_VERSION'])
                             .once
        expect(service).to receive(:latest_successful_ref)
                             .with(ReleaseTools::Project::GitlabWorkhorse)
                             .and_return(component_versions['GITLAB_WORKHORSE_VERSION'])
                             .once
        expect(service).to receive(:latest_successful_ref)
                             .with(ReleaseTools::Project::Gitaly)
                             .and_return(component_versions['GITALY_SERVER_VERSION'])
                             .once
        expect(service).to receive(:latest_successful_ref)
                             .with(ReleaseTools::Project::GitlabShell)
                             .and_return(component_versions['GITLAB_SHELL_VERSION'])
                             .once
        expect(service).to receive(:latest_successful_ref)
                             .with(ReleaseTools::Project::GitlabElasticsearchIndexer)
                             .and_return(component_versions['GITLAB_ELASTICSEARCH_INDEXER_VERSION'])
                             .once
        expect(internal_client).not_to receive(:create_commit)

        without_dry_run do
          service.execute
        end
      end
    end
  end
end
