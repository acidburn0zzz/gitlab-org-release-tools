# frozen_string_literal: true

module ReleaseTools
  module Project
    class GitlabMailroom
      def self.gem_name
        'mail_room'
      end

      def self.version_file
        'MAILROOM_VERSION'
      end
    end
  end
end
