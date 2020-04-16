# frozen_string_literal: true

module ReleaseTools
  module ReleaseManagers
    # Represents all defined Release Managers
    class Definitions
      extend Forwardable
      include Enumerable

      attr_accessor :config_file
      attr_reader :all

      def_delegator :@all, :each

      class << self
        extend Forwardable

        def_delegator :new, :allowed?
        def_delegator :new, :sync!
      end

      def initialize(config_file = nil)
        @config_file = config_file ||
          File.expand_path('../../../config/release_managers.yml', __dir__)

        reload!
      end

      def allowed?(username)
        any? { |user| user.production.casecmp?(username) }
      end

      def reload!
        begin
          content = YAML.load_file(config_file)
          raise ArgumentError, "#{config_file} contains no data" if content.blank?
        rescue Errno::ENOENT
          raise ArgumentError, "#{config_file} does not exist!"
        end

        @all = content.map { |name, hash| User.new(name, hash) }
      end

      def sync!
        release_managers = active_release_managers

        dev_client.sync_membership(release_managers.collect(&:dev))
        production_client.sync_membership(release_managers.collect(&:production))
        ops_client.sync_membership(release_managers.collect(&:ops))

        ReleaseManagers::SyncResult.new([dev_client, production_client, ops_client])
      end

      private

      def dev_client
        @dev_client ||= ReleaseManagers::Client.new(:dev)
      end

      def production_client
        @production_client ||= ReleaseManagers::Client.new(:production)
      end

      def ops_client
        @ops_client ||= ReleaseManagers::Client.new(:ops)
      end

      def active_release_managers
        active = Schedule.new.active_release_managers_usernames
        all.select { |user| active.include?(user.production) }
      end

      # Represents a single entry from the configuration file
      class User
        attr_reader :name
        attr_reader :dev, :production, :ops

        def initialize(name, hash)
          if hash['gitlab.com'].nil?
            raise ArgumentError, "No `gitlab.com` value for #{name}"
          end

          @name = name

          @production = hash['gitlab.com']
          @dev = hash['gitlab.org'] || production
          @ops = hash['ops.gitlab.net'] || production
        end
      end
    end
  end
end
