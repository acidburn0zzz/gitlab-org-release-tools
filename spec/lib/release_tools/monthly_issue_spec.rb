# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::MonthlyIssue do
  it_behaves_like 'issuable #initialize'

  describe '#title' do
    it "returns the issue title" do
      issue = described_class.new(version: ReleaseTools::Version.new('8.3.5-rc1'))

      expect(issue.title).to eq 'Release 8.3'
    end
  end

  describe '#description' do
    it "includes the version number" do
      issue = described_class.new(version: ReleaseTools::Version.new('8.3.0'))

      content = issue.description

      expect(content).to include("Tag `8.3.0`")
    end

    it "includes the slack channel" do
      issue = described_class.new(version: ReleaseTools::Version.new('8.3.0'))

      content = issue.description

      expect(content).to include('`#f_upcoming_release`')
    end
  end

  describe '#labels' do
    it 'returns a list of labels' do
      issue = described_class.new(version: double)

      expect(issue.labels).to eq 'Monthly Release,team::Delivery'
    end
  end

  describe '#assignees' do
    it 'returns the assignee IDs' do
      issue = described_class.new(version: ReleaseTools::Version.new('11.8'))
      schedule = instance_spy(ReleaseTools::ReleaseManagers::Schedule)

      allow(ReleaseTools::ReleaseManagers::Schedule)
        .to receive(:new)
        .and_return(schedule)

      allow(schedule)
        .to receive(:ids_for_version)
        .with(issue.version)
        .and_return([1, 2])

      expect(issue.assignees).to eq([1, 2])
    end
  end
end
