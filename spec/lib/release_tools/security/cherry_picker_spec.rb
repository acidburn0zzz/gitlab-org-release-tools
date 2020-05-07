# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Security::CherryPicker do
  let(:client) { double(:client) }

  let(:web_url) do
    'https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/1'
  end

  let(:merge_request) do
    double(
      :merge_request,
      target_branch: 'master',
      merge_commit_sha: 'aaa',
      project_id: 1,
      web_url: web_url
    )
  end

  subject(:picker) { described_class.new(client, merge_request) }

  before do
    allow(ReleaseTools::AutoDeployBranch).to receive(:current_name)
      .and_return('X-Y-auto-deploy-YYYYMMDD')

    allow(client)
      .to receive(:cherry_pick_commit)
  end

  describe '#execute' do
    context 'when the feature is enabled' do
      before do
        enable_feature(:security_cherry_picker)
      end

      context 'when the merge request has a merge commit sha' do
        it 'cherry picks the commit into auto-deploy' do
          expect(client).to receive(:cherry_pick_commit).with(
            merge_request.project_id,
            merge_request.merge_commit_sha,
            ::ReleaseTools::AutoDeployBranch.current_name
          )

          picker.execute
        end

        it 'handles failed cherry-picks' do
          expect(client).to receive(:cherry_pick_commit)
            .and_raise(gitlab_error(:BadRequest, code: 400))

          expect { picker.execute }.not_to raise_error
        end
      end

      context 'when the merge request does not have a merge commit sha' do
        let(:merge_request) do
          double(
            :merge_request,
            target_branch: 'master',
            merge_commit_sha: '',
            project_id: 1,
            web_url: 'https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/1'
          )
        end

        it 'skips the cherry pick' do
          expect(client).not_to receive(:cherry_pick_commit)

          picker.execute
        end
      end
    end

    context 'when the feature is disabled' do
      it 'does not executes the cherry pick' do
        disable_feature(:security_cherry_picker)

        expect(client).not_to receive(:cherry_pick_commit)

        picker.execute
      end
    end
  end
end
