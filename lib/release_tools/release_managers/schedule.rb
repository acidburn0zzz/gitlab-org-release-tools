# frozen_string_literal: true

module ReleaseTools
  module ReleaseManagers
    # Obtaining of release managers for a given major/minor release.
    class Schedule
      # Raised when release managers for the specified version can't be found
      VersionNotFoundError = Class.new(StandardError)

      # The base interval for retrying operations that failed, in seconds.
      #
      # This is set higher than the default as obtaining the release managers
      # schedule can time out, and it often takes a while before these requests
      # stop timing out.
      RETRY_INTERVAL = 5

      SCHEDULE_YAML = 'https://gitlab.com/gitlab-com/www-gitlab-com/raw/master/data/release_managers.yml'

      def initialize
        @schedule_yaml = nil
      end

      # Returns usernames of release managers at the time of request.
      #
      # @return [Array<String>]
      def active_release_managers_usernames
        version = version_for_date(DateTime.now)
        usernames_for_version(version)
      end

      # Returns the scheduled major.minor version for the given date.
      #
      # @param [Date|Time] date
      # @return [ReleaseTools::Version|NilClass]
      def version_for_date(date)
        # The release month ends at the 22nd, so for any date after that we want
        # the version for the month _after_ it; not the current month. Take this
        # schedule for example:
        #
        # | Month    | Version |
        # |:---------|:--------|
        # | January  | 12.0    |
        # | February | 12.1    |
        #
        # On January 21st, the next scheduled version is 12.0. On January 23rd
        # we already released 12.0, so the next scheduled version is 12.1; not
        # 12.0.
        date = date.next_month if date.day > 22

        # We process the schedule in reverse order (newer to older), as it's
        # more likely we are interested in a more recent/future date compared to
        # an older one.
        schedule_yaml.reverse_each do |row|
          row_date = Date.strptime(row['date'], '%B %dnd, %Y')

          if row_date.year == date.year && row_date.month == date.month
            return Version.new(row['version'])
          end
        end

        nil
      end

      # Returns the user IDs of the release managers for the current version.
      # Used to assign to resources such as Issues.
      #
      # @param [ReleaseTools::Version] version
      # @return [Array<Integer>]
      def ids_for_version(version)
        authorized_release_managers(version).collect(&:id)
      end

      # Returns the usernames of the release managers for the current version.
      # Used to add/remove access to groups at various GitLab instances.
      #
      # @param [ReleaseTools::Version] version
      # @return [Array<String>]
      def usernames_for_version(version)
        authorized_release_managers(version).collect(&:username)
      end

      # Returns an Array of users authorized for release manager tasks for current version.
      #
      # @param [ReleaseTools::Version] version
      # @return [Array<Gitlab::ObjectifiedHash>]
      def authorized_release_managers(version)
        release_manager_names_from_yaml(version).map do |name|
          group_members.fetch(name) do |key|
            raise KeyError, "#{key} is not an authorized release manager"
          end
        end
      end

      # Returns a Hash mapping release manager names with all their attributes.
      #
      # @return [Hash<String, Gitlab::ObjectifiedHash>]
      def group_members
        members =
          begin
            ReleaseManagers::Client.new.members
          rescue StandardError
            []
          end

        members.each_with_object({}) do |user, hash|
          hash[user.name] = user
        end
      end

      # Returns an Array of release manager names for the current version.
      #
      # @param [ReleaseTools::Version] version
      # @return [Array<String>]
      def release_manager_names_from_yaml(version)
        not_found = -> { raise VersionNotFoundError }
        minor = version.to_minor

        names = schedule_yaml
          .find(not_found) { |row| row['version'] == minor }

        names['manager_americas'] | names['manager_apac_emea']
      end

      # @return [Array<Hash>]
      def schedule_yaml
        @schedule_yaml ||=
          begin
            YAML.safe_load(download_schedule)
          rescue StandardError
            []
          end
      end

      private

      def download_schedule
        Retriable.retriable(base_interval: RETRY_INTERVAL) do
          HTTP.get(SCHEDULE_YAML).to_s
        end
      end
    end
  end
end
