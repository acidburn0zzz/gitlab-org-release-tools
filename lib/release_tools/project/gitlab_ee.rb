# frozen_string_literal: true

module ReleaseTools
  module Project
    class GitlabEe < BaseProject
      REMOTES = {
        canonical: 'git@gitlab.com:gitlab-org/gitlab.git',
        dev:       'git@dev.gitlab.org:gitlab/gitlab-ee.git',
        security:  'git@gitlab.com:gitlab-org/security/gitlab.git'
      }.freeze

      class Components
        class Mailroom
          def self.gem_name
            'mail_room'
          end

          def self.version_file
            'MAILROOM_VERSION'
          end
        end
      end
    end
  end
end
