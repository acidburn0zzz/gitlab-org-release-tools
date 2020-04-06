# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Qa::IssuableOmitterByLabels do
  let(:permitted) do
    double("permitted mr", labels: %w[devops::create documentation bug])
  end

  let(:unpermitted) do
    double("unpermitted mr", labels: %w[devops::plan Quality])
  end

  let(:permitted_but_no_team_labels) do
    double("documentation only mr", labels: %w[documentation])
  end

  let(:merge_requests) do
    [
      permitted,
      unpermitted,
      permitted_but_no_team_labels
    ]
  end

  subject { described_class.new(merge_requests).execute }

  it 'excludes merge requests with Omit labels' do
    expect(subject).not_to include(unpermitted)
  end

  it 'includes permitted merge requests' do
    expect(subject).to include(permitted)
  end

  it 'excludes documentation merge requests without team labels' do
    expect(subject).not_to include(permitted_but_no_team_labels)
  end
end
