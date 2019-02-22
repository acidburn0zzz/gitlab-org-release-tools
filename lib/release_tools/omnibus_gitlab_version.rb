# frozen_string_literal: true

module ReleaseTools
  class OmnibusGitlabVersion < Version
    VERSION_REGEX = %r{
      \A(?<major>\d+)
      \.(?<minor>\d+)
      (\.(?<patch>\d+))?
      (\+)?
      (?<rc>rc(?<rc_number>\d*))?
      (\.)?
      (?<edition>ce|ee)?
      (\.\d+)?\z
    }x

    def ee?
      edition == 'ee'
    end

    def to_ce
      return self unless ee?

      self.class.new(to_s.sub('+ee', '+ce'))
    end

    def to_ee
      return self if ee?

      self.class.new(to_s.sub('+ce', '+ee'))
    end

    def edition
      @edition ||= extract_from_version(:edition, fallback: 'ce')
    end

    def tag
      str = +"#{to_patch}+"
      str << "rc#{rc}." if rc?
      str << (ee? ? 'ee' : 'ce')
      str << '.0'
    end
  end
end
