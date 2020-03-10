# frozen_string_literal: true

module ReleaseTools
  module BranchCreation
    Result = Struct.new(:project, :branch, :response)

    def gitlab_client
      ReleaseTools::GitlabClient
    end

    def ignoring_duplicates
      yield
    rescue Gitlab::Error::Conflict, Gitlab::Error::BadRequest => ex
      if ex.message.match?('already exists')
        # no-op for idempotency
      else
        raise
      end
    end

    def create_branch_from_ref(project, branch, ref, client = gitlab_client)
      logger&.warn('Branch creation will be ignored because of TEST env') if dry_run?
      logger&.info('Creating branch', name: branch, from: ref, project: project.path)

      return if dry_run?

      ignoring_duplicates do
        Result.new(project, branch, client.create_branch(branch, ref, project))
      end
    end
  end
end
