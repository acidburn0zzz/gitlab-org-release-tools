# frozen_string_literal: true

module ReleaseTools
  module Project
    class GitlabEe < BaseProject
      REMOTES = {
        canonical: 'git@gitlab.com:gitlab-org/gitlab.git',
        dev:       'git@dev.gitlab.org:gitlab/gitlab-ee.git',
        security:  'git@gitlab.com:gitlab-org/security/gitlab.git'
      }.freeze

      # Returns a Hash of `gem_name => variable_name` pairs
      # Gem names are regular expressions to allow for renames
      # and backwards compatibility
      #
      # The variables are used in CNG image configurations.
      def self.gems
        {
          '^(gitlab-)?mail_room$': 'MAILROOM_VERSION'
        }
      end
    end
  end
end
