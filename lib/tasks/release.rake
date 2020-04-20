namespace :release do
  desc 'Create a release task issue'
  task :issue, [:version] do |_t, args|
    version = get_version(args)

    if version.monthly?
      issue = ReleaseTools::MonthlyIssue.new(version: version)
    else
      issue = ReleaseTools::PatchIssue.new(version: version)
    end

    create_or_show_issue(issue)
  end

  desc 'Merges valid merge requests into preparation branches'
  task :merge, [:version] do |_t, args|
    pick = lambda do |project, version|
      target = ReleaseTools::PreparationMergeRequest
        .new(project: project, version: version)

      ReleaseTools.logger.info(
        'Picking into preparation merge requests',
        project: project,
        version: version,
        target: target.branch_name
      )

      ReleaseTools::CherryPick::Service
        .new(project, version, target)
        .execute
    end

    version = get_version(args).to_ee

    pick[ReleaseTools::Project::GitlabEe, version]
    pick[ReleaseTools::Project::OmnibusGitlab, version.to_ce]
  end

  desc 'Prepare for a new release'
  task :prepare, [:version] do |_t, args|
    version = get_version(args)

    Rake::Task['release:issue'].execute(version: version)

    if version.monthly?
      service = ReleaseTools::Services::MonthlyPreparationService.new(version)

      service.create_label
    else
      # GitLab EE
      version = version.to_ee
      merge_request = ReleaseTools::PreparationMergeRequest
        .new(project: ReleaseTools::Project::GitlabEe, version: version)
      merge_request.create_branch!
      create_or_show_merge_request(merge_request)

      # Omnibus
      version = version.to_ce
      merge_request = ReleaseTools::PreparationMergeRequest
        .new(project: ReleaseTools::Project::OmnibusGitlab, version: version)
      merge_request.create_branch!
      create_or_show_merge_request(merge_request)
    end
  end

  desc 'Create a QA issue'
  task :qa, [:from, :to] do |_t, args|
    version = get_version(version: args[:to].sub(/\Av/, ''))

    build_qa_issue(version, args[:from], args[:to])
  end

  desc 'Create stable branches for a new release'
  task :stable_branch, [:version, :source] do |_t, args|
    version = get_version(args)

    if version.monthly?
      service = ReleaseTools::Services::MonthlyPreparationService.new(version)
      service.create_stable_branches(args[:source])
    end
  end

  desc "Check a release's build status"
  task :status, [:version] do |t, args|
    version = get_version(args)

    status = ReleaseTools::BranchStatus.for([version])

    status.each_pair do |project, results|
      results.each do |result|
        ReleaseTools.logger.tagged(t.name) do
          ReleaseTools.logger.info(project, result.to_h)
        end
      end
    end

    ReleaseTools::Slack::ChatopsNotification.branch_status(status)
  end

  desc 'Tag a new release'
  task :tag, [:version] do |_t, args|
    version = get_version(args)

    if skip?('ce')
      ReleaseTools.logger.warn('Skipping release for CE')
    else
      ce_version = version.to_ce

      ReleaseTools.logger.info('Starting CE release', version: ce_version)
      ReleaseTools::Release::GitlabCeRelease.new(ce_version).execute
    end

    if skip?('ee')
      ReleaseTools.logger.warn('Skipping release for EE')
    else
      ee_version = version.to_ee

      ReleaseTools.logger.info('Starting EE release', version: ee_version)
      ReleaseTools::Release::GitlabEeRelease.new(ee_version).execute
    end
  end

  desc 'Tracks a deployment using the GitLab API'
  task :track_deployment, [:environment, :status, :version] do |_, args|
    env = args[:environment]
    version = args[:version]
    meta = ReleaseTools::Deployments::Metadata.new(version)

    ReleaseTools::SharedStatus.as_security_release(meta.security_release?) do
      tracker = ReleaseTools::Deployments::DeploymentTracker
        .new(env, args[:status], version)

      deployments = tracker.track

      Raven.capture do
        ReleaseTools::Deployments::MergeRequestLabeler
          .new
          .label_merge_requests(env, deployments)
      end

      Raven.capture do
        ReleaseTools::Deployments::ReleasedMergeRequestNotifier
          .notify(env, deployments, version)
      end

      previous, latest = tracker.qa_commit_range

      if previous && latest
        ReleaseTools
          .logger
          .info('Attempting to create QA issue', from: previous, until: latest)

        build_qa_issue(get_version(version: version), previous, latest)
      end
    end
  end

  desc 'Tags a release candidate if needed'
  task :tag_scheduled_rc do
    unless ReleaseTools::Feature.enabled?(:tag_scheduled_rc)
      ReleaseTools.logger.info('Automatic tagging of RCs is not enabled')
      next
    end

    version = ReleaseTools::AutomaticReleaseCandidate.new.prepare

    ReleaseTools.logger.info('Tagging automatic RC', version: version)

    Rake::Task['release:tag'].invoke(version)
  end

  namespace :gitaly do
    desc 'Tag a new release'
    task :tag, [:version] do |_, args|
      version = get_version(args)

      ReleaseTools::Release::GitalyRelease.new(version, tag_from_master_head: true).execute
    end
  end

  namespace :helm do
    desc 'Tag a new release'
    task :tag, [:charts_version, :gitlab_version] do |_t, args|
      charts_version = ReleaseTools::HelmChartVersion.new(args[:charts_version]) if args[:charts_version] && !args[:charts_version].empty?
      gitlab_version = ReleaseTools::HelmGitlabVersion.new(args[:gitlab_version]) if args[:gitlab_version] && !args[:gitlab_version].empty?

      # At least one of the versions must be provided in order to tag
      if (!charts_version && !gitlab_version) || (charts_version && !charts_version.valid?) || (gitlab_version && !gitlab_version.valid?)
        ReleaseTools.logger.warn('Version number must be in the following format: X.Y.Z')
        exit 1
      end

      ReleaseTools.logger.info(
        'Chart release',
        charts_version: charts_version,
        gitlab_version: gitlab_version
      )
      ReleaseTools::Release::HelmGitlabRelease.new(charts_version, gitlab_version).execute
    end
  end
end
