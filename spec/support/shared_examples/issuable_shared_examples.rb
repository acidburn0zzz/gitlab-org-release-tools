# frozen_string_literal: true

RSpec.shared_examples 'issuable #initialize' do
  it 'accepts arbitrary attributes as arguments' do
    issuable = described_class.new(foo: 'bar')

    expect(issuable.foo).to eq('bar')
  end

  it 'accepts a block' do
    issuable = described_class.new do |new_issuable|
      new_issuable.foo = 'bar'
    end

    expect(issuable.foo).to eq('bar')
  end
end

RSpec.shared_examples 'issuable #create' do |create_issuable_method|
  it 'calls ReleaseTools::GitlabClient.create_issue' do
    expect(ReleaseTools::GitlabClient)
      .to receive(create_issuable_method)
      .with(subject, subject.project)

    subject.create
  end
end

RSpec.shared_examples 'issuable #update' do |update_issuable_method|
  it 'calls ReleaseTools::GitlabClient.update_issue' do
    expect(ReleaseTools::GitlabClient)
      .to receive(update_issuable_method)
      .with(subject, subject.project)

    subject.update
  end
end

RSpec.shared_examples 'issuable #accept' do |accept_issuable_method|
  it 'calls ReleaseTools::GitlabClient.create_issue' do
    expect(ReleaseTools::GitlabClient)
      .to receive(accept_issuable_method)
      .with(subject, subject.project)

    subject.accept
  end
end

RSpec.shared_examples 'issuable #remote_issuable' do |find_issuable_method|
  it 'delegates to ReleaseTools::GitlabClient' do
    expect(ReleaseTools::GitlabClient)
      .to receive(find_issuable_method)
      .with(subject, subject.project)

    subject.remote_issuable
  end

  context 'when remote issuable does not exist' do
    it 'does not memoize the value' do
      expect(ReleaseTools::GitlabClient).to receive(find_issuable_method).twice
        .with(subject, subject.project).and_return(nil)

      2.times { subject.remote_issuable }
    end
  end

  context 'when remote issuable exists' do
    it 'memoizes the remote issuable' do
      expect(ReleaseTools::GitlabClient).to receive(find_issuable_method).once
        .with(subject, subject.project).and_return(double)

      2.times { subject.remote_issuable }
    end
  end
end

RSpec.shared_examples 'issuable #url' do
  it 'returns the remote_issuable url' do
    remote_issuable = instance_double('dummy remote_issuable', web_url: 'https://example.com/')
    expect(subject).to receive(:remote_issuable).and_return(remote_issuable)
    expect(subject.url).to eq 'https://example.com/'
  end
end
