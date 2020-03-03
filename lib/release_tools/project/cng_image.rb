# frozen_string_literal: true

module ReleaseTools
  module Project
    class CNGImage < BaseProject
      REMOTES = {
        canonical: 'git@gitlab.com:gitlab-org/build/CNG.git',
        security:  'git@gitlab.com:gitlab-org/security/charts/components/images.git',
        dev:       'git@dev.gitlab.org:gitlab/charts/components/images.git'
      }.freeze
    end
  end
end
