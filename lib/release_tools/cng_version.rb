# frozen_string_literal: true

module ReleaseTools
  class CNGVersion < Version
    CNG_SINGLE_BRANCH_VERSION = ReleaseTools::Version.new('13.0.0')

    # For CNG, we have a single stable branch starting with version specified
    # in the env variable CNG_SINGLE_BRANCH_VERSION. So, we are stripping off
    # `-ee` suffix.
    def stable_branch(ee: false)
      super.tap do |branch|
        branch.chomp!('-ee') if self >= CNG_SINGLE_BRANCH_VERSION
      end
    end
  end
end
