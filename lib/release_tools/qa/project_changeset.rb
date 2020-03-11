# frozen_string_literal: true

module ReleaseTools
  module Qa
    class ProjectChangeset
      attr_reader :project, :from, :to, :default_client

      def initialize(project:, from:, to:, default_client: ReleaseTools::GitlabClient)
        @project = project
        @from = from
        @to = to
        @default_client = default_client

        verify_refs!(from, to)
      end

      def merge_requests
        @merge_requests ||= gather_merge_requests
      end

      def commits
        @commits ||= default_client.compare(project, from: from, to: to).commits
      end

      def shas
        commits.map { |commit| commit['id'] }
      end

      private

      def alternate_client
        if default_client == ReleaseTools::GitlabDevClient
          ReleaseTools::GitlabClient
        else
          ReleaseTools::GitlabDevClient
        end
      end

      def gather_merge_requests
        commits.each_with_object([]) do |commit, mrs|
          commit['message'].match(/See merge request (?<path>\S*)!(?<iid>\d+)/) do |match|
            mrs << retrieve_merge_request(match[:path], match[:iid])
          end
        end
      end

      def retrieve_merge_request(path, iid)
        dev_path = path.dup

        # HACK (rspeicher): Handle MRs merged into renamed EE project
        # TODO (rspeicher): We should be able to safely remove this sometime around December 2019
        path.gsub!(/-ee$/, '')

        project = OpenStruct.new(path: path, dev_path: dev_path)

        Retriable.retriable do
          begin
            default_client.merge_request(project, iid: iid)
          rescue Gitlab::Error::NotFound
            alternate_client.merge_request(project, iid: iid)
          end
        end
      end

      def verify_refs!(*refs)
        refs.each do |ref|
          begin
            default_client.commit(project, ref: ref)
          rescue Gitlab::Error::NotFound
            raise ArgumentError.new("Invalid ref for this repository: #{ref}")
          end
        end
      end
    end
  end
end
