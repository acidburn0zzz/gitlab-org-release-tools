# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Qa::IssuableOmitterByLabels do
  let(:permitted) do
    double("permitted mr", labels: %w[group::access documentation bug])
  end

  let(:unpermitted) do
    double("unpermitted mr", labels: %w[group::access Quality])
  end

  let(:merge_requests) do
    [
      permitted,
      unpermitted
    ]
  end

  subject { described_class.new(merge_requests).execute }

  it 'excludes merge requests with Omit labels' do
    expect(subject).not_to include(unpermitted)
  end

  it 'includes permitted merge requests' do
    expect(subject).to include(permitted)
  end
end
