# frozen_string_literal: true

module ReleaseTools
  module CherryPick
    # Performs automated cherry picking to a target branch for the specified
    # version.
    #
    # For the given project, this service will look for merged merge requests on
    # that project labeled `Pick into X.Y` and attempt to cherry-pick their merge
    # commits into the target merge request for the specified version.
    #
    # It will post a comment to each merge request with the status of the pick,
    # and a final summary message with the list of picked and unpicked merge
    # requests for the release managers to perform any further manual actions.
    class Service
      include ::SemanticLogger::Loggable

      attr_reader :project
      attr_reader :version
      attr_reader :target

      # project - ReleaseTools::Project object
      # version - ReleaseTools::Version object
      # target  - ReleaseTools::PreparationMergeRequest or
      #           ReleaseTools::AutoDeployBranch object
      def initialize(project, version, target)
        @project = project
        @version = version
        @target = target

        assert_version!
        assert_target!

        @target_branch = @target.branch_name

        @results = []
      end

      def execute
        return [] unless pickable_mrs.any?

        pickable_mrs.auto_paginate do |merge_request|
          cherry_pick(merge_request)
        end

        cancel_redundant_pipelines

        notifier.summary(
          @results.select(&:success?),
          @results.select(&:failure?)
        )

        notifier.blog_post_summary(@results.select(&:success?))

        @results
      end

      private

      attr_reader :repository

      def assert_version!
        raise "Invalid version provided: `#{version}`" unless version.valid?
      end

      def assert_target!
        raise 'Invalid cherry-pick target provided' unless target.exists?
      end

      def client
        ReleaseTools::GitlabClient
      end

      def cancel_redundant_pipelines
        return unless ENV['FEATURE_CANCEL_REDUNDANT']
        return if SharedStatus.dry_run?

        client.cancel_redundant_pipelines(project, ref: @target_branch)
      end

      def notifier
        if SharedStatus.dry_run?
          @notifier ||= ConsoleNotifier.new(version, target: target)
        else
          @notifier ||= CommentNotifier.new(version, target: target)
        end
      end

      def cherry_pick(merge_request)
        result = nil

        if allowed?(merge_request)
          unless SharedStatus.dry_run?
            client.cherry_pick(
              project,
              ref: merge_request.merge_commit_sha,
              target: @target_branch
            )
          end

          result = Result.new(merge_request, :success)
        else
          result = Result.new(merge_request, :denied, 'Merge request does not have S1 or S2 label')
        end
      rescue Gitlab::Error::Error => ex
        result = Result.new(merge_request, :failure)

        Raven.capture_exception(ex) unless ex.is_a?(Gitlab::Error::BadRequest)
      ensure
        record_result(result)
      end

      def allowed?(merge_request)
        case version
        when ReleaseTools::AutoDeploy::Version
          merge_request.labels.include?('S1') || merge_request.labels.include?('S2')
        else
          true
        end
      end

      def record_result(result)
        @results << result
        log_result(result)
        notifier.comment(result)
      end

      def log_result(result)
        payload = {
          project: project,
          target: target.branch_name,
          merge_request: result.url
        }

        if result.success?
          logger.info('Cherry-pick merged', payload)
        else
          logger.warn('Cherry-pick failed', payload)
        end
      end

      def pickable_mrs
        @pickable_mrs ||=
          client.merge_requests(
            project,
            state: 'merged',
            labels: PickIntoLabel.for(version),
            order_by: 'created_at',
            sort: 'asc'
          )
      end
    end
  end
end
