# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Security::MergeRequestValidator do
  describe '#validate' do
    it 'validates the merge request' do
      # All these methods are tested separately, so we just want to make sure
      # they're called from the `validate` method.
      merge_request = double(:merge_request)
      client = double(:client)
      validator = described_class.new(merge_request, client)

      validation_methods = %i[
        validate_pipeline_status
        validate_merge_status
        validate_work_in_progress
        validate_pending_tasks
        validate_milestone
        validate_merge_request_template
        validate_reviewed
        validate_target_branch
        validate_discussions
        validate_labels
        validate_closing_security_issue
      ]

      validation_methods.each do |method|
        allow(validator).to receive(method)
      end

      validator.validate

      validation_methods.each do |method|
        expect(validator).to have_received(method)
      end
    end
  end

  describe '#validate_pipeline_status' do
    let(:merge_request) { double(:merge_request) }
    let(:client) { double(:client) }
    let(:validator) { described_class.new(merge_request, client) }

    it 'adds an error when no pipeline could be found' do
      allow(ReleaseTools::Security::Pipeline)
        .to receive(:latest_for_merge_request)
        .with(merge_request, client)
        .and_return(nil)

      validator.validate_pipeline_status

      expect(validator.errors.first).to include('Missing pipeline')
    end

    it 'adds an error when the pipeline failed' do
      pipeline = double(:pipeline, failed?: true)

      allow(ReleaseTools::Security::Pipeline)
        .to receive(:latest_for_merge_request)
        .with(merge_request, client)
        .and_return(pipeline)

      validator.validate_pipeline_status

      expect(validator.errors.first).to include('Failing pipeline')
    end

    it 'adds an error when the pipeline is not yet finished' do
      pipeline =
        double(:pipeline, failed?: false, passed?: false, pending?: true)

      allow(ReleaseTools::Security::Pipeline)
        .to receive(:latest_for_merge_request)
        .with(merge_request, client)
        .and_return(pipeline)

      validator.validate_pipeline_status

      expect(validator.errors.first).to include('Pending pipeline')
    end

    it 'does not add an error when the pipeline passed' do
      pipeline = double(:pipeline, failed?: false, pending?: false)

      allow(ReleaseTools::Security::Pipeline)
        .to receive(:latest_for_merge_request)
        .with(merge_request, client)
        .and_return(pipeline)

      validator.validate_pipeline_status

      expect(validator.errors).to be_empty
    end
  end

  describe '#validate_merge_status' do
    it 'adds an error when the merge request can not be merged' do
      merge_request = double(:merge_request, merge_status: 'cannot_be_merged')
      client = double(:client)
      validator = described_class.new(merge_request, client)

      validator.validate_merge_status

      expect(validator.errors.first)
        .to include('The merge request can not be merged')
    end

    it 'does not add an error when the merge request can be merged' do
      merge_request = double(:merge_request, merge_status: 'can_be_merged')
      client = double(:client)
      validator = described_class.new(merge_request, client)

      validator.validate_merge_status

      expect(validator.errors).to be_empty
    end
  end

  describe '#validate_work_in_progress' do
    it 'adds an error when the merge request is a work in progress' do
      merge_request = double(:merge_request, title: 'WIP: kittens')
      client = double(:client)
      validator = described_class.new(merge_request, client)

      validator.validate_work_in_progress

      expect(validator.errors.first)
        .to include('The merge request is marked as a work in progress')
    end

    it 'does not add an error if the merge request is not a work in progress' do
      merge_request = double(:merge_request, title: 'kittens')
      client = double(:client)
      validator = described_class.new(merge_request, client)

      validator.validate_work_in_progress

      expect(validator.errors).to be_empty
    end
  end

  describe '#validate_pending_tasks' do
    it 'adds an error when the merge request has a pending task' do
      merge_request = double(:merge_request, description: '- [ ] Todo')
      client = double(:client)
      validator = described_class.new(merge_request, client)

      validator.validate_pending_tasks

      expect(validator.errors.first)
        .to include('There are one or more pending tasks')
    end

    it 'does not add an error when all tasks are completed' do
      merge_request = double(:merge_request, description: '- [x] Todo')
      client = double(:client)
      validator = described_class.new(merge_request, client)

      validator.validate_pending_tasks

      expect(validator.errors).to be_empty
    end
  end

  describe '#validate_milestone' do
    it 'adds an error when the milestone is missing' do
      merge_request = double(:merge_request, milestone: nil)
      client = double(:client)
      validator = described_class.new(merge_request, client)

      validator.validate_milestone

      expect(validator.errors.first)
        .to include('The merge request does not have a milestone')
    end

    it 'does not add an error when a milestone is present' do
      merge_request =
        double(:merge_request, milestone: double(:milestone, id: 1))

      client = double(:client)
      validator = described_class.new(merge_request, client)

      validator.validate_milestone

      expect(validator.errors).to be_empty
    end
  end

  describe '#validate_merge_request_template' do
    it 'adds an error when no tasks are present' do
      merge_request = double(:merge_request, description: 'Foo')
      client = double(:client)
      validator = described_class.new(merge_request, client)

      validator.validate_merge_request_template

      expect(validator.errors.first)
        .to include('The Security Release template is not used')
    end

    it 'does not add an error when at least one task is present' do
      merge_request = double(:merge_request, description: '- [X] Foo')
      client = double(:client)
      validator = described_class.new(merge_request, client)

      validator.validate_merge_request_template

      expect(validator.errors).to be_empty
    end
  end

  describe '#validate_reviewed' do
    it 'adds an error when the merge request is not reviewed' do
      merge_request = double(:merge_request, description: 'Foo')
      client = double(:client)
      validator = described_class.new(merge_request, client)

      validator.validate_reviewed

      expect(validator.errors.first)
        .to include('The merge request is not reviewed')
    end

    it 'does not add an error when the merge request is reviewed' do
      merge_request =
        double(:merge_request, description: '* [x] Assign to a reviewer')

      client = double(:client)
      validator = described_class.new(merge_request, client)

      validator.validate_reviewed

      expect(validator.errors).to be_empty
    end

    it 'does not add an error when the merge request is reviewed using a manual edit' do
      merge_request =
        double(:merge_request, description: '- [X] Assign to a reviewer')

      client = double(:client)
      validator = described_class.new(merge_request, client)

      validator.validate_reviewed

      expect(validator.errors).to be_empty
    end
  end

  describe '#validate_target_branch' do
    it 'adds an error when the merge request is targeting an invalid branch' do
      merge_request = double(:merge_request, target_branch: 'foo')
      client = double(:client)
      validator = described_class.new(merge_request, client)

      validator.validate_target_branch

      expect(validator.errors.first).to include('The target branch is invalid')
    end

    it 'does not add an error when the merge request targets a stable branch' do
      merge_request = double(:merge_request, target_branch: '11-8-stable')
      client = double(:client)
      validator = described_class.new(merge_request, client)

      validator.validate_target_branch

      expect(validator.errors).to be_empty
    end

    it 'does not add an error when the merge request targets master' do
      merge_request = double(:merge_request, target_branch: 'master')
      client = double(:client)
      validator = described_class.new(merge_request, client)

      validator.validate_target_branch

      expect(validator.errors).to be_empty
    end
  end

  describe '#validate_discussions' do
    it 'adds an error when there are unresolved discussions' do
      client = double(:client)
      response = double(:response)
      merge_request = double(:merge_request, project_id: 1, iid: 2)
      discussion1 = double(notes: [{ 'resolvable' => false }])
      discussion2 =
        double(notes: [{ 'resolvable' => true, 'resolved' => false }])

      allow(response)
        .to receive(:auto_paginate)
        .and_yield(discussion1)
        .and_yield(discussion2)

      allow(client)
        .to receive(:merge_request_discussions)
        .and_return(response)

      validator = described_class.new(merge_request, client)

      validator.validate_discussions

      expect(validator.errors.first)
        .to include('There are unresolved discussions')
    end

    it 'does not add an error when there are no unresolved discussions' do
      client = double(:client)
      response = double(:response)
      merge_request = double(:merge_request, project_id: 1, iid: 2)
      discussion = double(notes: [{ 'resolvable' => false }])

      allow(response)
        .to receive(:auto_paginate)
        .and_yield(discussion)

      allow(client)
        .to receive(:merge_request_discussions)
        .and_return(response)

      validator = described_class.new(merge_request, client)

      validator.validate_discussions

      expect(validator.errors).to be_empty
    end
  end

  describe '#validate_labels' do
    it 'adds an error when the security label is missing' do
      merge_request = double(:merge_request, labels: [])
      client = double(:client)
      validator = described_class.new(merge_request, client)

      validator.validate_labels

      expect(validator.errors.first)
        .to include('The merge request is missing the ~security label')
    end

    it 'does not add an error when the security label is present' do
      merge_request = double(:merge_request, labels: %w[security])
      client = double(:client)
      validator = described_class.new(merge_request, client)

      validator.validate_labels

      expect(validator.errors).to be_empty
    end
  end

  describe '#validate_closing_security_issue' do
    let(:client) { double(:client) }

    context 'when the merge request is targeting master' do
      it 'adds an error if the merge request does not close the security issue when merged' do
        merge_request = double(:merge_request,
                               iid: 1,
                               project_id: 1,
                               target_branch: 'master',
                               description: 'Some invalid description')

        allow(client)
          .to receive(:merge_request_closes_issues)
          .with(merge_request.project_id, merge_request.iid)
          .and_return([])

        validator = described_class.new(merge_request, client)
        validator.validate_closing_security_issue

        expect(validator.errors.first)
          .to include('The merge request must close the security implementation issue')
      end

      it 'does not add an error if the merge request closes the security issue when merged' do
        security_issue = double(:issue, web_url: 'gitlab-org/security/gitlab/1')

        merge_request = double(:merge_request,
                               iid: 1,
                               project_id: 1,
                               target_branch: 'master',
                               description: 'Some valid description. Closes #1')

        allow(client)
          .to receive(:merge_request_closes_issues)
          .with(merge_request.project_id, merge_request.iid)
          .and_return([security_issue])

        validator = described_class.new(merge_request, client)
        validator.validate_closing_security_issue

        expect(validator.errors).to be_empty
      end
    end

    context 'when the merge request is not targeting master' do
      it "does not add an error if the merge request includes 'Fixes #1' in its description" do
        merge_request = double(:merge_request,
                               iid: 1,
                               project_id: 1,
                               target_branch: '12-9-stable-ee',
                               description: 'Some valid description. Fixes #1')

        validator = described_class.new(merge_request, client)
        validator.validate_closing_security_issue

        expect(validator.errors).to be_empty
      end
    end
  end
end
