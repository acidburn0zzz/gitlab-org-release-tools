# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::ReleaseManagers::Schedule do
  let(:schedule) { described_class.new }
  let(:version) { ReleaseTools::Version.new('11.8') }

  let(:yaml) do
    <<~YAML
      - version: '11.8'
        date: February 22nd, 2019
        manager_americas:
          - Robert Speicher
        manager_apac_emea:
          - Yorick Peterse
    YAML
  end

  before do
    # Prevent retry delay from slowing down specs
    stub_const("#{described_class}::RETRY_INTERVAL", 0)
  end

  describe '#version_for_month' do
    context 'when there are releases scheduled' do
      before do
        allow(schedule)
          .to receive(:schedule_yaml)
          .and_return(YAML.safe_load(yaml))
      end

      it 'returns the version for the date' do
        expect(schedule.version_for_date(Date.new(2019, 2, 2))).to eq(version)
      end

      it 'returns nil when there is no matching release' do
        expect(schedule.version_for_date(Date.new(2005, 2, 2))).to be_nil
      end
    end

    context 'when there are no releases scheduled at all' do
      it 'returns nil' do
        allow(schedule)
          .to receive(:schedule_yaml)
          .and_return([])

        expect(schedule.version_for_date(Date.new(2019, 2, 2))).to be_nil
      end
    end
  end

  describe '#ids_for_version' do
    it 'returns the IDs of the release managers' do
      allow(schedule)
        .to receive(:authorized_manager_ids)
        .and_return('Robert Speicher' => 1, 'Yorick Peterse' => 2)

      allow(schedule)
        .to receive(:release_manager_names_from_yaml)
        .and_return(['Robert Speicher', 'Yorick Peterse'])

      expect(schedule.ids_for_version(version)).to eq([1, 2])
    end
  end

  describe '#authorized_manager_ids' do
    it 'returns a Hash mapping release manager names to their user IDs' do
      client = instance_spy(ReleaseTools::ReleaseManagers::Client)

      allow(ReleaseTools::ReleaseManagers::Client)
        .to receive(:new)
        .and_return(client)

      allow(client)
        .to receive(:members)
        .and_return([
          double(:member, name: 'Robert Speicher', id: 1),
          double(:member, name: 'Yorick Peterse', id: 2)
        ])

      expect(schedule.authorized_manager_ids)
        .to eq('Robert Speicher' => 1, 'Yorick Peterse' => 2)
    end
  end

  describe '#release_manager_names_from_yaml' do
    context 'when no release manager data is available' do
      it 'returns an empty Array' do
        allow(schedule)
          .to receive(:schedule_yaml)
          .and_return([])

        expect { schedule.release_manager_names_from_yaml(version) }
          .to raise_error(described_class::VersionNotFoundError)
      end
    end

    context 'when release manager data is present' do
      it 'returns the names of the release managers' do
        allow(schedule)
          .to receive(:schedule_yaml)
          .and_return(YAML.safe_load(yaml))

        expect(schedule.release_manager_names_from_yaml(version))
          .to eq(['Robert Speicher', 'Yorick Peterse'])
      end
    end
  end

  describe '#schedule_yaml' do
    context 'when the download succeeds' do
      it 'returns the release manager data' do
        response = double(:response, to_s: yaml)

        allow(HTTP)
          .to receive(:get)
          .and_return(response)

        expect(schedule.schedule_yaml.length).to eq(1)
      end
    end

    context 'when the download fails' do
      it 'returns an empty Array' do
        allow(HTTP)
          .to receive(:get)
          .and_raise(Errno::ENOENT)

        expect(schedule.schedule_yaml).to be_empty
      end
    end
  end
end
