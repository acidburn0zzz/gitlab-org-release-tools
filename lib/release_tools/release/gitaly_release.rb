# frozen_string_literal: true

module ReleaseTools
  module Release
    class GitalyRelease < AutoDeployedComponentRelease
      def project
        Project::Gitaly
      end
    end
  end
end
