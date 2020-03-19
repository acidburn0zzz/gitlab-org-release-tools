# frozen_string_literal: true

module ReleaseTools
  module Services
    class BasePublishService
      include ::SemanticLogger::Loggable

      class PipelineNotFoundError < StandardError
        def initialize(version)
          super("Pipeline not found for #{version}")
        end
      end

      def initialize(version)
        @version = version
      end

      def play_stages
        raise NotImplementedError
      end

      def release_versions
        raise NotImplementedError
      end

      def project
        raise NotImplementedError
      end

      def execute
        release_versions.each do |version|
          pipeline = client
            .pipelines(project, scope: :tags, ref: version)
            .first

          raise PipelineNotFoundError.new(version) unless pipeline

          logger.info('Finding manual jobs', pipeline: pipeline.web_url, version: version)

          triggers = client
            .pipeline_jobs(project, pipeline.id, scope: :manual)
            .auto_paginate
            .select { |job| play_stages.include?(job.stage) }

          if triggers.any?
            triggers.each do |job|
              if SharedStatus.dry_run?
                logger.warn('Would play job', name: job.name, url: job.web_url)
              else
                logger.info('Play job', name: job.name, url: job.web_url)
                client.job_play(project_path, job.id)
              end
            end
          else
            logger.warn('No jobs found')
          end
        end
      end

      private

      def project_path
        project.dev_path
      end

      def client
        @client ||= GitlabDevClient
      end
    end
  end
end
