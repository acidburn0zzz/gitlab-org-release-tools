# frozen_string_literal: true

module ReleaseTools
  class GemfileParser
    include ::SemanticLogger::Loggable

    class VersionNotFoundError < StandardError
      def initialize(gem_name)
        super("Unable to find a version for gem `#{gem_name}`")
      end
    end

    def initialize(filecontent)
      @filecontent = filecontent

      @parsed_file = Bundler::LockfileParser.new(@filecontent)
    end

    def gem_version(gem_name)
      spec = @parsed_file.specs.find { |x| x.name.match?(gem_name.to_s) }

      raise VersionNotFoundError, gem_name if spec.nil?

      spec.version.to_s.tap do |version|
        logger.trace('Version from gemfile', gem: gem_name, version: version)
      end
    end
  end
end
