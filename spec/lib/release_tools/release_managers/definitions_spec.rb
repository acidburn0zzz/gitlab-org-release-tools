# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::ReleaseManagers::Definitions do
  subject { described_class.new(fixture) }

  let(:fixture) { File.expand_path('../../../fixtures/release_managers.yml', __dir__) }

  describe 'class delegators' do
    it 'delegates .allowed?' do
      expect(described_class).to respond_to(:allowed?)
    end

    it 'delegates .sync!' do
      expect(described_class).to respond_to(:sync!)
    end
  end

  describe '#all' do
    it 'returns an array of User objects' do
      expect(subject.all)
        .to all(be_kind_of(described_class::User))
    end

    it 'is enumerable' do
      expect(subject).to respond_to(:any?)
    end
  end

  describe '#allowed?' do
    it 'allows a defined member, case-insensitively' do
      expect(subject).to be_allowed('RSpeicher')
    end

    it 'disallows an undefined member' do
      expect(subject).not_to be_allowed('invalid-member')
    end
  end

  describe '#reload!' do
    it 'raises `ArgumentError` if the config file is missing' do
      expect { described_class.new('foo.yml') }
        .to raise_error(ArgumentError, 'foo.yml does not exist!')
    end

    it 'raises `ArgumentError` if the config file is empty' do
      allow(YAML).to receive(:load_file).and_return({})

      expect { described_class.new('foo.yml') }
        .to raise_error(ArgumentError, 'foo.yml contains no data')
    end
  end

  describe '#sync!' do
    before do
      schedule = instance_spy(ReleaseTools::ReleaseManagers::Schedule)

      allow(ReleaseTools::ReleaseManagers::Schedule)
        .to receive(:new)
        .and_return(schedule)

      allow(schedule)
        .to receive(:active_release_managers_usernames)
        .and_return(["jameslopez", "new-team-member", "rspeicher"])
    end

    def client_spy(client_to_spy_on)
      client_spy = spy

      case client_to_spy_on
      when :dev
        allow(subject).to receive(:dev_client).and_return(client_spy)
        allow(subject).to receive(:production_client).and_return(double.as_null_object)
        allow(subject).to receive(:ops_client).and_return(double.as_null_object)
      when :ops
        allow(subject).to receive(:dev_client).and_return(double.as_null_object)
        allow(subject).to receive(:production_client).and_return(double.as_null_object)
        allow(subject).to receive(:ops_client).and_return(client_spy)
      else
        allow(subject).to receive(:dev_client).and_return(double.as_null_object)
        allow(subject).to receive(:production_client).and_return(client_spy)
        allow(subject).to receive(:ops_client).and_return(double.as_null_object)
      end

      client_spy
    end

    it 'syncs dev usernames' do
      client = client_spy(:dev)

      subject.sync!

      expect(client).to have_received(:sync_membership)
        .with(%w[james new-team-member-dev rspeicher])
    end

    it 'syncs production usernames' do
      client = client_spy(:production)

      subject.sync!

      expect(client).to have_received(:sync_membership)
        .with(%w[jameslopez new-team-member rspeicher])
    end

    it 'syncs ops usernames' do
      client = client_spy(:ops)

      subject.sync!

      expect(client).to have_received(:sync_membership)
        .with(%w[jameslopez new-team-member-ops rspeicher])
    end

    it 'returns a `SyncResult`' do
      client_spy(:production)

      expect(subject.sync!).to be_a(ReleaseTools::ReleaseManagers::SyncResult)
    end
  end

  describe described_class::User do
    describe 'initialize' do
      it 'raises ArgumentError when no `gitlab.com` value is provided' do
        expect { described_class.new('foo', bar: :baz) }
          .to raise_error(ArgumentError, /gitlab\.com/)
      end
    end
  end
end
