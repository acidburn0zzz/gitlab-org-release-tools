# frozen_string_literal: true

module ReleaseTools
  class Preflight
    include ::SemanticLogger::Loggable

    def self.check
      check_ci_environment
      check_mirroring
      check_variables
    end

    def self.check_ci_environment
      return unless ENV['CI']
      return if ENV['CI_JOB_STAGE'] == 'test'
      return if ops?

      logger.warn(
        'CI job running outside of Ops environment',
        stage: ENV['CI_JOB_STAGE'],
        name: ENV['CI_JOB_NAME'],
        url: ENV['CI_JOB_URL']
      )
    end

    # Ensure mirroring for release-tools from Canonical to Ops is working
    def self.check_mirroring
      return true unless ENV['CI']
      return true unless ops?

      project = ReleaseTools::Project::ReleaseTools
      mirrors = ReleaseTools::GitlabClient.remote_mirrors(project)

      # For now we're just going to assume that all mirrors are critical
      mirrors.each do |mirror|
        next unless mirror.last_error

        logger.fatal(
          'release-tools mirror error',
          mirror: mirror.url,
          error: mirror.last_error
        )
      end
    rescue ::Gitlab::Error::Error, Errno::ETIMEDOUT => ex
      logger.warn(
        'Unable to determine mirror status',
        project: project,
        error_code: ex.response_status,
        error_message: ex.message
      )
    end

    def self.check_variables
      {
        'DEV_API_PRIVATE_TOKEN' => 'RELEASE_BOT_DEV_TOKEN',
        'GITLAB_API_PRIVATE_TOKEN' => 'RELEASE_BOT_PRODUCTION_TOKEN',
        'OPS_API_PRIVATE_TOKEN' => 'RELEASE_BOT_OPS_TOKEN',
        'VERSION_API_PRIVATE_TOKEN' => 'RELEASE_BOT_VERSION_TOKEN'
      }.each do |old, replace|
        next unless ENV[old].present?

        warn "Using `#{old}` is deprecated and will soon be removed. Use `#{replace}` instead."

        ENV[replace] ||= ENV[old]
      end
    end

    def self.ops?
      ENV['CI_JOB_URL'].include?('ops.gitlab.net')
    end
  end
end
