# frozen_string_literal: true

module ReleaseTools
  class ClientWrapper
    include ::SemanticLogger::Loggable

    PRODUCTION_ENDPOINT = 'https://gitlab.com/api/v4'
    OPS_ENDPOINT = 'https://ops.gitlab.net/api/v4'
    DEV_ENDPOINT = 'https://dev.gitlab.org/api/v4'

    # Don't wrap these methods, send them through directly
    #
    # Logging arguments for these methods may reveal sensitive information.
    SKIP_METHODS = %i[get post put delete url_encode].freeze

    def self.production
      client = ::Gitlab.client(
        endpoint: PRODUCTION_ENDPOINT,
        private_token: ENV['RELEASE_BOT_PRODUCTION_TOKEN']
      )

      new(client)
    end

    def self.dev
      client = ::Gitlab.client(
        endpoint: DEV_ENDPOINT,
        private_token: ENV['RELEASE_BOT_DEV_TOKEN']
      )

      new(client)
    end

    def self.ops
      client = ::Gitlab.client(
        endpoint: OPS_ENDPOINT,
        private_token: ENV['RELEASE_BOT_OPS_TOKEN']
      )

      new(client)
    end

    def initialize(gem_client)
      @client = gem_client

      if Feature.enabled?(:log_httparty)
        @client.httparty ||= { logger: logger, log_level: :trace }
      end
    end

    def method_missing(name, *args, &block)
      return super unless @client.respond_to?(name)

      return @client.send(name, *args, &block) if SKIP_METHODS.include?(name)

      args.map! do |arg|
        project_class?(arg) ? project_path(arg) : arg
      end

      logger.trace(name, args)

      begin
        @client.send(name, *args, &block)
      rescue ::Gitlab::Error::Error => ex
        logger.warn(
          'GitLab API error',
          method: name,
          args: args,
          status: ex.response_status,
          error: ex.message
        )

        raise ex
      end
    end

    def respond_to_missing?(name, include_private = false)
      @client.respond_to?(name) || super
    end

    private

    def project_class?(arg)
      arg.respond_to?(:dev_path)
    end

    # Translate a `BaseProject` object to a `namespace/project` String based on
    # the client's endpoint
    def project_path(project)
      if @client.endpoint.include?(DEV_ENDPOINT)
        project.try(:dev_path) || project.path
      elsif @client.endpoint.include?(OPS_ENDPOINT)
        project.try(:ops_path) || project.path
      elsif SharedStatus.security_release?
        project.try(:security_path) || project.path
      else
        project.path
      end
    end
  end
end
