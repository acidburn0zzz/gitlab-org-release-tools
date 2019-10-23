# frozen_string_literal: true

module ReleaseTools
  class Version < String
    VERSION_REGEX = %r{
      \A(?<major>\d+)
      \.(?<minor>\d+)
      (\.(?<patch>\d+))?
      (-(?<rc>rc(?<rc_number>\d*)))?
      (-\h+\.\h+)?
      (-ee)?\z
    }x.freeze

    def initialize(version_string)
      super(version_string)

      if valid? && extract_from_version(:patch, fallback: nil).nil?
        rc? ? super(to_rc(rc)) : super(to_patch)
      end
    end

    def ==(other)
      if other.respond_to?(:to_ce)
        to_ce.eql?(other.to_ce)
      else
        super
      end
    end

    def <=>(other)
      return nil unless other.is_a?(Version)
      return 0 if self == other

      if major > other.major ||
          (major >= other.major && minor > other.minor) ||
          (major >= other.major && minor >= other.minor && patch > other.patch) ||
          (major >= other.major && minor >= other.minor && patch >= other.patch && other.rc?)

        rc? && other.rc? ? (rc - other.rc) : 1
      else
        -1
      end
    end

    def ee?
      end_with?('-ee')
    end

    def milestone_name
      to_minor
    end

    def monthly?
      patch.zero? && !rc?
    end

    def patch?
      patch.positive?
    end

    def major
      @major ||= extract_from_version(:major).to_i
    end

    def minor
      @minor ||= extract_from_version(:minor).to_i
    end

    def patch
      @patch ||= extract_from_version(:patch).to_i
    end

    def rc
      return unless rc?

      @rc ||= extract_from_version(:rc_number).to_i
    end

    def rc?
      return @is_rc if defined?(@is_rc)

      @is_rc = extract_from_version(:rc, fallback: false)
    end

    def version?
      self =~ self.class::VERSION_REGEX
    end

    def release?
      valid? && !rc? && !ee?
    end

    def next_major
      "#{major + 1}.0.0"
    end

    def next_minor
      "#{major}.#{minor + 1}.0"
    end

    def previous_minor
      version_string =
        if minor.positive?
          "#{major}.#{minor - 1}.0"
        else
          # When we are creating a new major release, we can not retrieve the
          # previous stable branch from the current version. Instead we must
          # find the last minor version of the previous major release.
          version = Versions.last_version_for_major(major - 1)

          unless version
            raise "The last version before #{self} could not be found"
          end

          version
        end

      version_string
    end

    def previous_patch
      return unless patch?

      new_patch = self.class.new("#{major}.#{minor}.#{patch - 1}")

      ee? ? new_patch.to_ee : new_patch
    end

    def next_patch
      new_patch = self.class.new("#{major}.#{minor}.#{patch + 1}")

      ee? ? new_patch.to_ee : new_patch
    end

    def stable_branch(ee: false)
      to_minor.tr('.', '-').tap do |prefix|
        if ee || ee?
          prefix << '-stable-ee'
        else
          prefix << '-stable'
        end
      end
    end

    def tag(ee: false)
      tag_for(self, ee: ee)
    end

    def previous_tag(ee: false)
      return unless patch?
      return if rc?

      tag_for(previous_patch, ee: ee)
    end

    # Convert the current version to CE if it isn't already
    def to_ce
      return self unless ee?

      self.class.new(to_s.gsub(/-ee$/, ''))
    end

    # Convert the current version to EE if it isn't already
    def to_ee
      return self if ee?

      self.class.new("#{self}-ee")
    end

    def to_minor
      "#{major}.#{minor}"
    end

    def to_omnibus(ee: false)
      str = +"#{to_patch}+"

      str << "rc#{rc}." if rc?
      str << (ee ? 'ee' : 'ce')
      str << '.0'
    end

    def to_docker(ee: false)
      to_omnibus(ee: ee).tr('+', '-')
    end

    def to_patch
      "#{major}.#{minor}.#{patch}"
    end

    def to_rc(number = 1)
      (+"#{to_patch}-rc#{number}").tap do |version|
        version << '-ee' if ee?
      end
    end

    def valid?
      self.class::VERSION_REGEX.match?(self)
    end

    private

    def tag_for(version, ee: false)
      version = version.to_ee if ee

      "v#{version}"
    end

    def extract_from_version(part, fallback: 0)
      match_data = self.class::VERSION_REGEX.match(self)
      if match_data && match_data.names.include?(part.to_s) && match_data[part]
        String.new(match_data[part])
      else
        fallback
      end
    end
  end
end
