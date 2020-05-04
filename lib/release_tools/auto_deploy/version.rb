# frozen_string_literal: true

require 'release_tools/auto_deploy_branch'
require 'release_tools/version'

module ReleaseTools
  module AutoDeploy
    class Version < ::ReleaseTools::Version
      def self.from_branch(branch_name)
        version = branch_name
          .sub(/\A(?:security\/)?(\d+)-(\d+)-auto-deploy.*/, '\1.\2')

        new(version).tap do |instance|
          instance.stable_branch = branch_name
        end
      end

      # Overrides Version#stable_branch because we don't care about arguments
      def stable_branch(*)
        @stable_branch
      end

      def stable_branch=(value)
        @stable_branch = ReleaseTools::AutoDeployBranch.new(value.to_s)
      end

      alias auto_deploy_branch stable_branch

      def to_ce
        super.tap do |instance|
          instance.stable_branch = stable_branch
        end
      end

      def to_ee
        super.tap do |instance|
          instance.stable_branch = stable_branch
        end
      end
    end
  end
end
