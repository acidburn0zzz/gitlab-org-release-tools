# frozen_string_literal: true

module ReleaseTools
  class Preflight
    include ::SemanticLogger::Loggable

    def self.check
      check_ci_environment
      check_variables
    end

    def self.check_ci_environment
      return unless ENV['CI']
      return if ENV['CI_JOB_STAGE'] == 'test'
      return if ENV['CI_JOB_URL'].include?('ops.gitlab.net')

      logger.warn(
        'CI job running outside of Ops environment',
        stage: ENV['CI_JOB_STAGE'],
        name: ENV['CI_JOB_NAME'],
        url: ENV['CI_JOB_URL']
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
  end
end
