# frozen_string_literal: true

module ReleaseTools
  class Preflight
    def self.check
      check_variables
    end

    def self.check_variables
      {
        'DEV_API_PRIVATE_TOKEN' => 'RELEASE_BOT_DEV_TOKEN',
        'GITLAB_API_PRIVATE_TOKEN' => 'RELEASE_BOT_PRODUCTION_TOKEN',
        'OPS_API_PRIVATE_TOKEN' => 'RELEASE_BOT_OPS_TOKEN'
      }.each do |old, replace|
        next unless ENV[old].present?

        warn "Using `#{old}` is deprecated and will soon be removed. Use `#{replace}` instead."

        ENV[replace] ||= ENV[old]
      end
    end
  end
end
