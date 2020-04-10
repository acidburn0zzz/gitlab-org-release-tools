# frozen_string_literal: true

module ReleaseTools
  class Issuable < OpenStruct
    def initialize(*args)
      super
      yield self if block_given?
    end

    def type
      self.class.to_s.demodulize.titlecase
    end

    def description
      ERB
        .new(template, trim_mode: '-') # Omit blank lines when using `<% -%>`
        .result(binding)
    end

    def project
      self[:project] || default_project
    end

    def project_id
      remote_issuable&.project_id
    end

    def author
      remote_issuable&.author
    end

    def iid
      remote_issuable&.iid
    end

    def created_at
      self[:created_at] = Time.parse(self[:created_at]) if self[:created_at]&.is_a?(String)

      super
    end

    def exists?
      !remote_issuable.nil?
    end

    def create
      raise NotImplementedError
    end

    def create?
      true
    end

    def remote_issuable
      raise NotImplementedError
    end

    def url
      remote_issuable.web_url
    end

    private

    def default_project
      ReleaseTools::Project::GitlabEe
    end

    def template
      File.read(template_path)
    end
  end
end
