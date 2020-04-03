# frozen_string_literal: true

module ReleaseTools
  module AutoDeploy
    module Tagger
      class Helm
        include ::SemanticLogger::Loggable

        PROJECT = Project::HelmGitlab
        TRIGGER_JOB = 'tag_auto_deploy'

        def initialize(target_branch, version_map)
          @target_branch = target_branch
          @version_map = version_map

          @helm_token = ENV.fetch('HELM_BUILD_TRIGGER_TOKEN') do |name|
            raise "Missing environment variable `#{name}`"
          end
        end

        def tag!(tag_name)
          logger.info('Tagging Helm chart', name: tag_name)

          trigger = client.run_trigger(
            PROJECT,
            @helm_token,
            @target_branch,
            trigger_variables(tag_name)
          )

          logger.info('Triggered pipeline', url: trigger.web_url)
        rescue ::Gitlab::Error::Error => ex
          logger.fatal(
            "Failed to trigger Helm chart tagging",
            name: tag_name,
            target: @target_branch,
            error_code: ex.response_status,
            error_message: ex.message
          )
        end

        private

        def trigger_variables(tag_name)
          inject_versions('AUTO_DEPLOY_TAG' => tag_name, 'TRIGGER_JOB' => TRIGGER_JOB)
        end

        def inject_versions(variables)
          @version_map.each do |component, version|
            variables["AUTO_DEPLOY_COMPONENT_#{component}"] = version
          end

          variables
        end

        def client
          ReleaseTools::GitlabClient
        end
      end
    end
  end
end
