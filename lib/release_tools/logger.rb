# frozen_string_literal: true

module ReleaseTools
  class Logger
    # rubocop:disable Metrics/MethodLength
    def self.setup
      SemanticLogger.application = 'release-tools'
      SemanticLogger.default_level = ENV.fetch('LOG_LEVEL', 'debug').to_sym
      SemanticLogger.push_tags('dry-run') if SharedStatus.dry_run?
      SemanticLogger.push_tags('security') if SharedStatus.security_release?

      if File.basename($PROGRAM_NAME) == 'rspec'
        # Overwrite each test run; meaningless in CI but nice for development
        SemanticLogger.add_appender(
          io: File.new('log/test.log', 'w'),
          formatter: NoProcessDefaultFormatter.new
        )
      else
        SemanticLogger.add_appender(
          io: $stdout,
          formatter: NoProcessColorFormatter.new
        )

        if ENV['ELASTIC_URL'] && ReleaseTools::Feature.enabled?(:log_elastic)
          SemanticLogger.add_appender(
            appender: :elasticsearch_http,
            url: ENV['ELASTIC_URL'],
            index: 'release_tools',
            host: ENV['CI_JOB_URL'],

            # Give ES more time to respond over HTTP
            open_timeout: 5.0,
            read_timeout: 5.0,
            continue_timeout: 5.0
          )
        end

        if ENV['SENTRY_DSN']
          require 'sentry-raven'

          Raven.user_context(
            git_user: SharedStatus.user,
            release_user: ENV['RELEASE_USER']
          )

          if ENV['CI_JOB_URL']
            Raven.extra_context(job_url: ENV['CI_JOB_URL'])
          end

          if ReleaseTools::Feature.enabled?(:log_sentry)
            SemanticLogger.add_appender(appender: :sentry, level: :fatal)
          end
        end
      end
    end
    # rubocop:enable Metrics/MethodLength

    # Remove process info from the default Color formatter
    class NoProcessColorFormatter < SemanticLogger::Formatters::Color
      # The default warn color is `BOLD`, but `YELLOW` looks better
      def initialize(**args)
        args[:color_map] ||= ::SemanticLogger::Formatters::Color::ColorMap.new(
          warn: ::SemanticLogger::AnsiColors::YELLOW
        )

        super
      end

      def process_info
        nil
      end
    end

    # Remove process info from the Default formatter
    class NoProcessDefaultFormatter < SemanticLogger::Formatters::Default
      def process_info
        nil
      end
    end
  end
end
