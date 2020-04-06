# frozen_string_literal: true

module ReleaseTools
  class GitlabDevClient < GitlabClient
    DEV_API_ENDPOINT = 'https://dev.gitlab.org/api/v4'

    def self.project_path(project)
      if project.respond_to?(:dev_path)
        project.dev_path
      else
        project
      end
    end

    def self.client
      @client ||=
        if Feature.enabled?(:client_wrapper)
          ReleaseTools::ClientWrapper.dev
        else
          Gitlab.client(
            endpoint: DEV_API_ENDPOINT,
            private_token: ENV['RELEASE_BOT_DEV_TOKEN'],
            httparty: httparty_opts
          )
        end
    end
  end
end
