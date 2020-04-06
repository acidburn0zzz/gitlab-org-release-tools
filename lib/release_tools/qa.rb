# frozen_string_literal: true

module ReleaseTools
  module Qa
    TEAM_LABELS = [
      'Community contribution',
      'Platform [DEPRECATED]',
      'Manage [DEPRECATED]',
      'devops::manage',
      'Plan [DEPRECATED]',
      'devops::plan',
      'Create [DEPRECATED]',
      'devops::create',
      'Verify [DEPRECATED]',
      'devops::verify',
      'Package [DEPRECATED]',
      'devops::package',
      'Release [DEPRECATED]',
      'devops::release',
      'Configure [DEPRECATED]',
      'devops::configure',
      'Serverless [DEPRECATED]',
      'group::serverless and paas',
      'Monitor [DEPRECATED]',
      'devops::monitor',
      'Secure [DEPRECATED]',
      'devops::secure',
      'Defend [DEPRECATED]',
      'devops::defend',
      'Growth [DEPRECATED]',
      'devops::growth',
      'Gitaly [DEPRECATED]',
      'group::gitaly',
      'Gitter [DEPRECATED]',
      'group::gitter',
      'Distribution [DEPRECATED]',
      'group::distribution',
      'Geo [DEPRECATED]',
      'group::geo',
      'Memory [DEPRECATED]',
      'group::memory',
      'Ecosystem [DEPRECATED]',
      'group::ecosystem',
      'group::search',
      'frontend',
      'database'
    ].freeze

    PERMITTED_WITH_TEAM_LABELS = [
      'documentation'
    ].freeze

    UNPERMITTED_LABELS = [
      'Quality',
      'QA',
      'meta',
      'test',
      'ci-build',
      'master:broken',
      'master:flaky',
      'CE upstream',
      'development guidelines',
      'static analysis',
      'rails5',
      'backstage'
    ].freeze

    PROJECTS = [
      ReleaseTools::Project::GitlabEe
    ].freeze

    ISSUE_PROJECT = ReleaseTools::Project::Release::Tasks
  end
end
