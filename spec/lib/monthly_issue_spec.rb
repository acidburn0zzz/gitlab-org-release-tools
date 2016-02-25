require 'spec_helper'

require 'monthly_issue'
require 'version'

describe MonthlyIssue do
  describe '#title' do
    it "returns the issue title" do
      issue = described_class.new(Version.new('8.3.5-rc1'))

      expect(issue.title).to eq 'Release 8.3'
    end
  end

  describe '#description' do
    it "includes ordinal date headers" do
      time = Time.new(2015, 12, 22)
      issue = described_class.new(spy, time)

      content = issue.description

      aggregate_failures do
        expect(content).to include('### 30th: (16 working days before the 22nd)')
        expect(content).to include('### 1st: (15 working days before the 22nd)')
        expect(content).to include('### Anytime beetween 1st (15 working days before the 22nd) and 16th (4 working days before the 22nd)')
        expect(content).to include('### 11th: (7 working days before the 22nd)')
        expect(content).to include('### Anytime beetween 17th (3 working days before the 22nd) and 21st (1 working day before the 22nd)')
        expect(content).to include('### 17th: (3 working days before the 22nd)')
        expect(content).to include('### 18th: (2 working days before the 22nd)')
        expect(content).to include('### 21st: (1 working day before the 22nd)')
      end
    end

    it "includes the RC version" do
      issue = described_class.new(Version.new('8.3.0'))

      content = issue.description

      expect(content).to include('GitLab 8.3.0-rc2 is available:')
    end

    it "includes stable branch names" do
      issue = described_class.new(Version.new('8.3.0-rc1'))

      content = issue.description

      expect(content).to include('Merge CE `8-3-stable` into EE `8-3-stable-ee`')
    end

    it "includes the version number" do
      issue = described_class.new(Version.new('8.3.0'))

      content = issue.description

      aggregate_failures do
        expect(content).to include("Try to do before 1100 CET: Tag and build (this is CI-automatized) the `8.3.0` version")
        expect(content).to include("Create the `8.3.0` version")
      end
    end
  end

  describe '#labels' do
    it 'returns a list of labels' do
      issue = described_class.new(double)

      expect(issue.labels).to eq 'Release'
    end
  end

  describe '#ordinal_date' do
    it "returns an ordinal date string" do
      time = Time.new(2015, 12, 22)
      issue = described_class.new(double, time)

      expect(issue.ordinal_date(5)).to eq '15th'
    end
  end
end
