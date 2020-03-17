module ReleaseTools
  class Pipeline
    include ::SemanticLogger::Loggable

    attr_reader :project, :sha

    def initialize(project, sha = nil, versions = nil)
      @project = project
      @sha = sha
      @token = ENV.fetch('OMNIBUS_BUILD_TRIGGER_TOKEN') do |name|
        raise "Missing environment variable `#{name}`"
      end
      @versions = versions
    end

    def find_and_wait
      tags = ReleaseTools::GitlabDevClient.tags(@project)
      matched_tags = tags.select do |k|
        if @project == 'gitlab/charts/gitlab' # our helm chart
          k.name =~ /\A\d+\.\d+\.\d+\+[\w\d]+\z/
        elsif @project == 'gitlab/omnibus-gitlab'
          k.name =~ /\A\d+\.\d+\.\d+\+[\w\d]+\.[\w\d]+\z/
        else
          raise 'invalid project defined'
        end
      end

      if matched_tags.empty?
        logger.fatal('No tags matched.', project: @project) if matched_tags.empty?
        exit 1
      end

      # TODO this feels dangerous, we are relying to queries to find a tag without
      # restriction to validate it's the tag that we want to monitor for.
      # If syncing is stopped or hung for whatever reason, we may end up waiting
      # on the wrong tag
      tag = matched_tags.first

      pipeline = ReleaseTools::GitlabDevClient.pipelines(@project, ref: tag.name).first

      ReleaseTools.logger.info("Found tag and pipeline", project: @project, ref: tag.name, pipeline: pipeline.id, url: pipeline.web_url)

      wait(pipeline.id)
    end

    def trigger
      logger.info('Trigger pipeline', project: project, sha: sha)

      trigger = ReleaseTools::GitlabDevClient.run_trigger(
        ReleaseTools::Project::OmnibusGitlab,
        @token,
        'master',
        build_variables
      )

      logger.info('Triggered pipeline', url: trigger.web_url)

      wait(trigger.id)
    end

    private

    def status(id)
      ReleaseTools::GitlabDevClient.pipeline(@project, id).status
    end

    def wait(id)
      interval = 60 # seconds
      max_duration = 3600 * 3 # 3 hours
      start = Time.now.to_i

      logger.info("Waiting on pipeline success", id: id, timeout: max_duration)

      logger.measure_info('Waiting for pipeline', metric: 'pipeline/waiting') do
        loop do
          if ReleaseTools::TimeUtil.timeout?(start, max_duration)
            raise "Pipeline timeout after waiting for #{max_duration} seconds."
          end

          case status(id)
          when 'created', 'pending', 'running'
            sleep(interval)
          when 'success', 'manual'
            break
          else
            raise 'Pipeline did not succeed.'
          end
        end
      end
    end

    def build_variables
      @versions.merge(
        'GITLAB_VERSION' => @sha,
        'NIGHTLY' => 'true',
        'ee' => @project == ReleaseTools::Project::GitlabEe
      )
    end
  end
end
