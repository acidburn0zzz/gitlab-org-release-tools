# frozen_string_literal: true

module ReleaseTools
  module Qa
    class IssuableOmitterByLabels
      attr_reader :issuables

      def initialize(issuables)
        @issuables = issuables
      end

      def execute
        issuables.select do |issuable|
          no_unpermitted_labels?(issuable) && permitted_labels?(issuable)
        end
      end

      private

      def no_unpermitted_labels?(issuable)
        (issuable.labels & SKIP_QA_ISSUER_LABELS).empty?
      end

      def permitted_labels?(issuable)
        (issuable.labels & QA_ISSUER_LABELS).any?
      end
    end
  end
end
