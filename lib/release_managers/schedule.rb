# frozen_string_literal: true

require 'yaml'
require 'httparty'

module ReleaseManagers
  # Obtaining of release managers for a given major/minor release.
  class Schedule
    SCHEDULE_YAML = 'https://gitlab.com/gitlab-com/www-gitlab-com/raw/master/data/release_managers.yml'

    # @param [Version] version
    def initialize(version)
      @version = version.to_minor
    end

    # Returns the user IDs of the release managers for the current version.
    #
    # @return [Array<Integer>]
    def ids
      mapping = authorized_manager_ids

      release_manager_names_from_yaml.map do |name|
        mapping.fetch(name) do |key|
          raise KeyError, "#{key} is not an authorized release manager"
        end
      end
    end

    # Returns a Hash mapping release manager names to their user IDs.
    #
    # @return [Hash<String, Integer>]
    def authorized_manager_ids
      members =
        begin
          ReleaseManagers::Client.new.members
        rescue
          []
        end

      members.each_with_object({}) do |user, hash|
        hash[user.name] = user.id
      end
    end

    # Returns an Array of release manager names for the current version.
    #
    # @return [Array<String>]
    def release_manager_names_from_yaml
      names = download_release_manager_names
        .find { |row| row['version'] == @version }

      if names
        names['manager_americas'] | names['manager_apac_emea']
      else
        []
      end
    end

    # @return [Array<Hash>]
    def download_release_manager_names
      YAML.safe_load(HTTParty.get(SCHEDULE_YAML).body)
    rescue
      []
    end
  end
end
