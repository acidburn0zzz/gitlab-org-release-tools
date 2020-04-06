# frozen_string_literal: true

module ReleaseTools
  module Project
    class GitlabElasticsearchIndexer < BaseProject
      REMOTES = {
        canonical: 'git@gitlab.com:gitlab-org/gitlab-elasticsearch-indexer.git',
        dev: 'git@dev.gitlab.org:gitlab/gitlab-elasticsearch-indexer.git',
        security: 'git@dev.gitlab.org:gitlab/gitlab-elasticsearch-indexer.git'
      }.freeze

      def self.version_file
        'GITLAB_ELASTICSEARCH_INDEXER_VERSION'
      end

      def self.security_client
        GitlabDevClient
      end
    end
  end
end
