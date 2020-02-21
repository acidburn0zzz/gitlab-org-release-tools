# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Qa::Ref do
  let(:stable_branch_ref) { '10-0-stable' }
  let(:release_tag_ref) { 'v10.0.0' }
  let(:rc_tag_ref) { 'v10.0.0-rc1' }

  context '#ref' do
    it 'returns the EE commit when using an auto deploy ref' do
      ref = described_class.new('v12.0.2019123-123456123456.456789456789')

      expect(ref.ref).to eq('123456123456')
    end

    it 'returns the ref as-is when using a regular tag' do
      ref = described_class.new('v12.0.0')

      expect(ref.ref).to eq('v12.0.0')
    end

    it 'returns the input ref for a patch version' do
      ref = described_class.new('v12.8.0-ee.0')

      expect(ref.ref).to eq('v12.8.0-ee.0')
    end
  end

  context '#for_project' do
    context 'for ee' do
      let(:project) { ReleaseTools::Project::GitlabEe }

      it 'outputs the stable branch ref' do
        ref = described_class.new(stable_branch_ref)

        expect(ref.for_project(project)).to eq('10-0-stable-ee')
      end

      it 'outputs the release tag ref' do
        ref = described_class.new(release_tag_ref)

        expect(ref.for_project(project)).to eq('v10.0.0-ee')
      end

      it 'outputs the rc tag ref' do
        ref = described_class.new(rc_tag_ref)

        expect(ref.for_project(project)).to eq('v10.0.0-rc1-ee')
      end

      it 'outputs the correct alternate branch ref' do
        ref = described_class.new('branch')

        expect(ref.for_project(project)).to eq('branch')
      end

      it 'outputs the correct master branch ref' do
        ref = described_class.new('master')

        expect(ref.for_project(project)).to eq('master')
      end

      it 'outputs the correct sha' do
        ref = described_class.new('cdb7aec191347cf004447b2d6124e5e394c033f4')

        expect(ref.for_project(project)).to eq('cdb7aec191347cf004447b2d6124e5e394c033f4')
      end
    end

    context 'for ce' do
      let(:project) { ReleaseTools::Project::GitlabCe }

      it 'outputs the stable branch ref' do
        ref = described_class.new(stable_branch_ref)

        expect(ref.for_project(project)).to eq('10-0-stable')
      end

      it 'outputs the release tag ref' do
        ref = described_class.new(release_tag_ref)

        expect(ref.for_project(project)).to eq('v10.0.0')
      end

      it 'outputs the rc tag ref' do
        ref = described_class.new(rc_tag_ref)

        expect(ref.for_project(project)).to eq('v10.0.0-rc1')
      end

      it 'outputs the correct alternate branch ref' do
        ref = described_class.new('branch')

        expect(ref.for_project(project)).to eq('branch')
      end

      it 'outputs the correct master branch ref' do
        ref = described_class.new('master')

        expect(ref.for_project(project)).to eq('master')
      end

      it 'outputs the correct sha' do
        ref = described_class.new('cdb7aec191347cf004447b2d6124e5e394c033f4')

        expect(ref.for_project(project)).to eq('cdb7aec191347cf004447b2d6124e5e394c033f4')
      end
    end
  end
end
