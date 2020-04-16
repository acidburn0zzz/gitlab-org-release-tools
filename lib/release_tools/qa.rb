# frozen_string_literal: true

module ReleaseTools
  module Qa
    TEAM_LABELS = [
      'Community contribution',
      'group::access',
      'group::compliance',
      'group::import',
      'group::analytics',
      'group::spaces',
      'group::project management',
      'group::portfolio management',
      'group::certify',
      'group::source code',
      'group::knowledge',
      'group::static site editor',
      'group::editor',
      'group::gitaly',
      'group::gitter',
      'group::ecosystem',
      'group::continuous integration',
      'group::runner',
      'group::testing',
      'group::package',
      'group::progressive delivery',
      'group::release management',
      'group::configure',
      'group::apm',
      'group::health',
      'group::static analysis',
      'group::dynamic analysis',
      'group::composition analysis',
      'group::fuzz testing',
      'group::vulnerability research',
      'group::container security',
      'group::threat insights',
      'group::acquisition',
      'group::conversion',
      'group::expansion',
      'group::retention',
      'group::fulfillment',
      'group::telemetry',
      'group::distribution',
      'group::geo',
      'group::memory',
      'group::global search',
      'group::database',
      'group::not_owned'
    ].freeze

    QA_ISSUER_LABELS = [
      'Community contribution',
      'bug',
      'feature',
      'backend',
      'frontend',
      'database'
    ].freeze

    SKIP_QA_ISSUER_LABELS = [
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
