# frozen_string_literal: true

module ReleaseTools
  module Qa
    class Ref
      TAG_REGEX = /(?<prefix>\w?)(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)(-rc?(?<rc>\d+))?/.freeze
      STABLE_BRANCH_REGEX = /^(?<major>\d+)-(?<minor>\d+)-(?<stable>stable)$/.freeze

      AUTO_DEPLOY_TAG_REGEX = /
        \A
        (?<prefix>\w?)
        (?<major>\d+)
        \.
        (?<minor>\d+)
        \.
        (?<patch>\d+)
        -
        (?<commit>\h{11,})
        \.
        (?<omnibus_commit>\h{11,})
        \z
      /x.freeze

      def initialize(ref)
        @ref = ref
      end

      def ref
        matches = @ref.match(AUTO_DEPLOY_TAG_REGEX)

        if matches && matches[:commit]
          matches[:commit]
        else
          @ref
        end
      end

      def for_project(project)
        if project == ReleaseTools::Project::GitlabEe && should_be_converted?
          "#{ref}-ee"
        else
          ref
        end
      end

      private

      def should_be_converted?
        tag? || stable_branch?
      end

      def tag?
        ref.match(TAG_REGEX)
      end

      def stable_branch?
        ref.match(STABLE_BRANCH_REGEX)
      end
    end
  end
end
