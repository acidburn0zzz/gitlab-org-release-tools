# frozen_string_literal: true

require 'semantic_logger'
require 'zeitwerk'

require 'colorize'
require 'erb'
require 'gitlab'
require 'http'
require 'open3'
require 'parallel'
require 'retriable'
require 'rugged'
require 'uri'
require 'yaml'

require 'active_support'
require 'active_support/core_ext/date'
require 'active_support/core_ext/date_time'
require 'active_support/core_ext/hash/transform_values'
require 'active_support/core_ext/integer'
require 'active_support/core_ext/numeric'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/indent'
require 'active_support/core_ext/string/inflections'
require 'active_support/inflector'

module ReleaseTools
  include ::SemanticLogger::Loggable
end

loader = Zeitwerk::Loader.new
loader.inflector.inflect(
  'cng_image' => 'CNGImage',
  'cng_image_release' => 'CNGImageRelease',
  'cng_publish_service' => 'CNGPublishService'
)
loader.push_dir(__dir__)
loader.setup

ReleaseTools::Logger.setup
ReleaseTools::Preflight.check
