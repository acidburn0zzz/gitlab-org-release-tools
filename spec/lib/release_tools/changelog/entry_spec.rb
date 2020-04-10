# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Changelog::Entry do
  def entry(hash)
    content = hash.to_yaml

    described_class.new('foo/bar', double(content: content))
  end

  describe 'initialize' do
    it 'parses blob content' do
      entry = entry('title' => 'Foo', 'merge_request' => 1234, 'author' => 'Joe Smith', 'type' => 'added')

      aggregate_failures do
        expect(entry.title).to eq 'Foo'
        expect(entry.id).to eq 1234
        expect(entry.author).to eq 'Joe Smith'
        expect(entry.type).to eq 'added'
      end
    end

    it 'parses a string' do
      data = {
        'title' => 'Foo',
        'merge_request' => 1234,
        'author' => 'Joe Smith',
        'type' => 'added'
      }

      entry = described_class.new('foo/bar', data.to_yaml)

      aggregate_failures do
        expect(entry.title).to eq 'Foo'
        expect(entry.id).to eq 1234
        expect(entry.author).to eq 'Joe Smith'
        expect(entry.type).to eq 'added'
      end
    end

    it 'handles a String-based ID' do
      entry = entry('merge_request' => '1234')

      expect(entry.id).to eq 1234
    end

    it 'handles a merge request reference' do
      entry = entry('merge_request' => '!1234')

      expect(entry.id).to eq 1234
    end

    it 'handles a merge request URL' do
      entry = entry('merge_request' => 'https://example.com/foo/bar/merge_requests/1234')

      expect(entry.id).to eq 1234
    end

    it 'handles invalid blob content' do
      blob = double(content: "---\ninvalid: yaml: here\n")

      expect { described_class.new('foo/bar', blob) }.not_to raise_error
    end

    it 'handles a non-existent type' do
      entry = entry('foo' => 'foo')

      expect(entry.type).to eq('other')
    end

    it 'handles an empty type' do
      entry = entry('type' => '')

      expect(entry.type).to eq('other')
    end

    it 'handles an invalid type' do
      entry = entry('type' => '*invalid_type!@#')

      expect(entry.type).to eq('other')
    end

    it 'handles any case of type' do
      entry = entry('type' => 'SecURIty')

      expect(entry.type).to eq('security')
    end
  end

  describe '#to_s' do
    it 'includes the title, ending in a period' do
      entry = entry('title' => 'Foo')

      expect(entry.to_s).to eq 'Foo.'
    end

    it 'removes duplicate trailing periods' do
      entry = entry('title' => 'Foo.')

      expect(entry.to_s).to eq 'Foo.'
    end

    it 'includes the merge request reference when available' do
      entry = entry('title' => 'Foo', 'merge_request' => 1234)

      expect(entry.to_s).to eq 'Foo. !1234'
    end

    it 'includes the author when available' do
      entry = entry('title' => 'Foo', 'merge_request' => nil, 'author' => 'Joe Smith')

      expect(entry.to_s).to eq 'Foo. (Joe Smith)'
    end

    it 'includes the merge request reference and author when available' do
      entry = entry('title' => 'Foo', 'merge_request' => 1234, 'author' => 'Joe Smith')

      expect(entry.to_s).to eq 'Foo. !1234 (Joe Smith)'
    end

    it 'does not include the type' do
      entry = entry('title' => 'Foo.', 'type' => 'added')

      expect(entry.to_s).not_to include('ADDED')
    end
  end

  describe '#valid?' do
    it 'returns false when title is missing' do
      entry = entry({})

      expect(entry).not_to be_valid
    end

    it 'returns true when title is present' do
      entry = entry('title' => 'Foo')

      expect(entry).to be_valid
    end
  end
end
