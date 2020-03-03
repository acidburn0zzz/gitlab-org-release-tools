namespace :security do
  # Undocumented; should be a pre-requisite for every task in this namespace!
  task :force_security do
    unless ReleaseTools::SharedStatus.critical_security_release?
      ENV['SECURITY'] = 'true'
    end
  end

  desc 'Create a security release task issue'
  task issue: :force_security do |_t, args|
    issue = ReleaseTools::SecurityPatchIssue.new(versions: args[:versions])

    create_or_show_issue(issue)
  end

  desc 'Merges valid security merge requests'
  task :merge, [:merge_master] => :force_security do |_t, args|
    merge_master =
      if args[:merge_master] && !args[:merge_master].empty?
        true
      else
        false
      end

    if ReleaseTools::Feature.enabled?(:security_mirror_toggle)
      ReleaseTools::Security::Mirrors.disable
    end

    ReleaseTools::Security::MergeRequestsMerger
      .new(ReleaseTools::Security::DevClient.new, merge_master: merge_master)
      .execute

    ReleaseTools::Security::MergeRequestsMerger
      .new(ReleaseTools::Security::Client.new, merge_master: merge_master)
      .execute
  end

  desc 'Prepare for a new security release'
  task prepare: :force_security do |_t, _args|
    issue_task = Rake::Task['security:issue']
    versions = []

    ReleaseTools::Versions.next_security_versions.each do |version|
      versions << get_version(version: version)
    end

    issue_task.execute(versions: versions)
  end

  desc 'Create a security QA issue'
  task :qa, [:from, :to] => :force_security do |_t, args|
    Rake::Task['release:qa'].invoke(*args)
  end

  desc "Check a security release's build status"
  task status: :force_security do |t, _args|
    status = ReleaseTools::BranchStatus.for_security_release

    status.each_pair do |project, results|
      results.each do |result|
        ReleaseTools.logger.tagged(t.name) do
          ReleaseTools.logger.info(project, result.to_h)
        end
      end
    end

    ReleaseTools::Slack::ChatopsNotification.branch_status(status)
  end

  desc 'Tag a new security release'
  task :tag, [:version] => :force_security do |_t, args|
    $stdout
      .puts "Security Release - using security repository only!\n"
      .colorize(:red)

    Rake::Task['release:tag'].invoke(*args)
  end

  desc 'Validates security merge requests'
  task validate: :force_security do
    ReleaseTools::Security::MergeRequestsValidator
      .new(ReleaseTools::Security::DevClient.new)
      .execute

    ReleaseTools::Security::MergeRequestsValidator
      .new(ReleaseTools::Security::Client.new)
      .execute
  end

  namespace :gitaly do
    desc 'Tag a new Gitaly security release'
    task :tag, [:version] => :force_security do |_, args|
      version = get_version(args)

      ReleaseTools::Release::GitalyRelease.new(version, tag_from_master_head: true).execute
    end
  end
end
