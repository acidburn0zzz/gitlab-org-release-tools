# frozen_string_literal: true

require 'unleash'

module ReleaseTools
  # Interface to feature flags for this project
  #
  # See https://gitlab.com/gitlab-org/release-tools/-/feature_flags
  class Feature
    include ::SemanticLogger::Loggable

    UNLEASH = ::Unleash::Client.new(
      url: ENV['FEATURE_INSTANCE_URL'],
      app_name: SemanticLogger.application,
      instance_id: ENV['FEATURE_INSTANCE_ID'],
      disable_metrics: true,
      logger: logger,
      log_level: :warn,
      disable_client: !ENV['FEATURE_INSTANCE_ID']
    )

    def self.enabled?(feature)
      logger.trace(__method__, feature: feature)

      UNLEASH.is_enabled?(feature.to_s)
    end

    def self.disabled?(feature)
      !enabled?(feature)
    end
  end
end
