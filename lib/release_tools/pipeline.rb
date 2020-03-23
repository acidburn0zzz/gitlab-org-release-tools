module ReleaseTools
  class Pipeline
    include ::SemanticLogger::Loggable

    attr_reader :project, :sha

    def initialize(project, ref)
      @project = project
      @ref = ref
    end

    def wait_for_success
      # TODO: figure out what to do if there's more than one pipeline, omnibus is an example of spinning
      # up 2 pipelines during a tag for X reason
      pipeline = ReleaseTools::GitlabDevClient.pipelines(@project, ref: @ref).first

      unless pipeline
        ReleaseTools.logger.fatal("Pipeline not found", project: @project, ref: @ref)
        exit 1
      end

      ReleaseTools.logger.info("Found tag and pipeline", project: @project, ref: @ref, url: pipeline.web_url)

      wait(pipeline.id)
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

      loop do
        if ReleaseTools::TimeUtil.timeout?(start, max_duration)
          raise "Pipeline timeout after waiting for #{max_duration} seconds."
        end

        case status(id)
        when 'created', 'pending', 'running'
          sleep(interval)
        when 'success'
          logger.info("Pipeline succeeded", project: @project, ref: @ref, id: id)
          break
        else
          logger.fatal("Pipeline did not succeed")
          exit 1
        end
      end
    end
  end
end
