# frozen_string_literal: true

module ReleaseTools
  class GitlabOpsClient < GitlabClient
    OPS_API_ENDPOINT = 'https://ops.gitlab.net/api/v4'

    def self.project_path(project)
      project.path
    end

    def self.client
      @client ||= Gitlab.client(
        endpoint: OPS_API_ENDPOINT,
        private_token: ENV['RELEASE_BOT_OPS_TOKEN'],
        httparty: httparty_opts
      )
    end
  end
end
