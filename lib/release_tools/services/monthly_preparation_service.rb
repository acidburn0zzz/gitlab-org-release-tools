# frozen_string_literal: true

module ReleaseTools
  module Services
    class MonthlyPreparationService
      include ::SemanticLogger::Loggable
      include BranchCreation

      GITLAB_COM_GPRD_ENVIRONMENT_ID = 1_178_942

      def initialize(version)
        @version = version
      end

      def gitlab_client
        ReleaseTools::GitlabClient
      end

      def create_label
        logger.info("Creating monthly Pick label", label: PickIntoLabel.for(@version))

        return if ReleaseTools::SharedStatus.dry_run?

        ignoring_duplicates do
          PickIntoLabel.create(@version)
        end
      end

      def create_stable_branches(source = 'master')
        ce_branch = @version.stable_branch(ee: false)
        ee_branch = @version.stable_branch(ee: true)
        omnibus_souce = source

        if source.nil?
          logger.info('Creating stable branch from last deployment production deployment')

          deployment = gitlab_client.last_deployment(Project::GitlabEe, GITLAB_COM_GPRD_ENVIRONMENT_ID)

          logger.info('Last deployment', ref: deployment.ref, sha: deployment.sha, date: deployment.created_at)

          source = deployment.sha
          omnibus_souce = deployment.ref
        end

        create_branch_from_ref(Project::GitlabEe, ee_branch, source)
        create_ce_stable_branch(ce_branch)
        create_branch_from_ref(Project::OmnibusGitlab, ce_branch, omnibus_souce)
        # CNG and Charts doesn't have an auto-deploy dependency, hence they
        # get created from master.
        create_branch_from_ref(Project::CNGImage, ce_branch, 'master')
        create_branch_from_ref(Project::CNGImage, ee_branch, 'master')

        # Helm charts follow different branching scheme
        create_helm_branch('master')
      end

      # For CE we want to base the stable branch on the previous stable branch.
      # This way we don't end up with commits from "master" that are
      # useless/reverted once we perform a FOSS sync from EE to CE. Including
      # those commits may lead one to believe unrelated changes are in CE, when
      # this is not the case.
      def create_ce_stable_branch(branch)
        source =
          Version.new(@version.previous_minor).stable_branch(ee: false)

        create_branch_from_ref(Project::GitlabCe, branch, source)
      end

      def create_helm_branch(source = 'master')
        project = ReleaseTools::Project::HelmGitlab
        repo = ReleaseTools::RemoteRepository.get(project.remotes)

        version_manager = ReleaseTools::Helm::VersionManager.new(repo)
        helm_version = version_manager.next_version(@version.to_ce)

        create_branch_from_ref(project, helm_version.stable_branch, source)
      ensure
        repo.cleanup
      end
    end
  end
end
