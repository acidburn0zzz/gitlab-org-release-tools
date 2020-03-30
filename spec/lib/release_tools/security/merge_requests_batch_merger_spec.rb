# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Security::MergeRequestsBatchMerger do
  let(:client) { double(:client) }
  let(:issue_crawler) { double(:issue_crawler) }
  let(:cherry_picker) { double(:cherry_picker) }

  let(:issue_result) do
    double(:result, processed: [], invalid: [], pending: Hash.new([]))
  end

  let(:batch_merger) { described_class.new(client) }

  before do
    allow(ReleaseTools::Security::IssueCrawler)
      .to receive(:new)
      .and_return(issue_crawler)

    allow(ReleaseTools::Security::IssueResult)
      .to receive(:new)
      .and_return(issue_result)

    allow(ReleaseTools::Security::CherryPicker)
      .to receive(:new)
      .and_return(cherry_picker)

    allow(ReleaseTools::Slack::ChatopsNotification)
      .to receive(:security_issues_processed)
      .and_return(nil)
  end

  describe '#execute' do
    context 'when security implementation issues are not ready' do
      it 'does not process the issues' do
        issue1 = double(:issue, iid: 1, merge_requests_ready?: false)
        issue2 = double(:issue, iid: 2, merge_requests_ready?: false)

        allow(issue_crawler)
          .to receive(:upcoming_security_issues_and_merge_requests)
          .and_return([issue1, issue2])

        expect(batch_merger)
          .not_to receive(:validated_merge_requests)

        expect(batch_merger)
          .not_to receive(:merge_in_batches)

        batch_merger.execute
      end
    end

    context 'with security issues ready to be processed' do
      let(:response) { double(:response) }
      let(:author) { double(:author, id: 1, username: 'joe') }

      let(:mr1) do
        double(
          :merge_request,
          iid: 1,
          project_id: 1,
          target_branch: 'master',
          web_url: 'https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/1',
          author: author
        )
      end

      let(:mr2) do
        double(
          :merge_request,
          iid: 2,
          project_id: 1,
          target_branch: '12-10-stable-ee',
          web_url: 'https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/2',
          author: author
        )
      end

      let(:mr3) do
        double(
          :merge_request,
          iid: 3,
          project_id: 1,
          target_branch: '12-9-stable-ee',
          web_url: 'https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/3',
          author: author
        )
      end

      let(:mr4) do
        double(
          :merge_request,
          iid: 4,
          project_id: 1,
          target_branch: '12-8-stable-ee',
          web_url: 'https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/4',
          author: author
        )
      end

      let(:merge_requests) do
        [mr1, mr2, mr3, mr4]
      end

      let(:issue1) do
        double(
          :issue,
          iid: 1,
          merge_requests_ready?: true,
          merge_requests: merge_requests,
          merge_request_targeting_master: mr1,
          merge_requests_targeting_stable: [mr2, mr3, mr4]
        )
      end

      let(:issue2) do
        double(
          :issue,
          iid: 2,
          merge_requests_ready?: true,
          merge_requests: merge_requests,
          merge_request_targeting_master: mr1,
          merge_requests_targeting_stable: [mr2, mr3, mr4]
        )
      end

      context 'with issues with invalid merge requests' do
        before do
          allow(issue_crawler)
          .to receive(:upcoming_security_issues_and_merge_requests)
          .and_return([issue1, issue2])

          allow(batch_merger)
            .to receive(:validated_merge_requests)
            .with(merge_requests)
            .and_return([[mr1], [mr2, mr3, mr4]])

          allow(client)
            .to receive(:update_merge_request)
            .and_return(response)

          allow(client)
            .to receive(:create_merge_request_discussion)
            .and_return(response)
        end

        it 'creates a discussion on the merge request targeting master' do
          expect(client)
            .to receive(:create_merge_request_discussion)
            .with(mr1.project_id, mr1.iid, body: an_instance_of(String))

          batch_merger.execute
        end

        it 'reassigns all the merge requests back to the author' do
          expect(client)
            .to receive(:update_merge_request)
            .exactly(8).times

          batch_merger.execute
        end

        it 'does not pick merge request targeting master into auto deploy branch' do
          expect(batch_merger)
            .not_to receive(:cherry_pick_into_auto_deploy)

          batch_merger.execute
        end

        it 'notifies the results' do
          expect(ReleaseTools::Slack::ChatopsNotification)
            .to receive(:security_issues_processed)

          batch_merger.execute
        end
      end

      context 'with issues with valid merge requests' do
        context 'when all the merge requests can be merged' do
          let(:mr1) do
            double(
              :merge_request,
              iid: 1,
              project_id: 1,
              target_branch: 'master',
              web_url: 'https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/1',
              author: author,
              merge_commit_sha: '1a2b3c'
            )
          end

          before do
            allow(issue_crawler)
              .to receive(:upcoming_security_issues_and_merge_requests)
              .and_return([issue1, issue2])

            allow(batch_merger)
              .to receive(:validated_merge_requests)
              .with(merge_requests)
              .and_return([[mr1, mr2, mr3, mr4], []])

            merged_mr = double(:merge_request,
                               merge_commit_sha: '1a2b3c',
                              web_url: 'https://gitlab.com/gitlab-org/security/gitlab/-/merge_requests/1')

            allow(client)
              .to receive(:accept_merge_request)
              .and_return(merged_mr)

            allow(cherry_picker)
              .to receive(:execute)
              .and_return(nil)
          end

          it 'merges the merge requests in batch' do
            expect(issue_result)
              .to receive(:pending)
              .twice

            expect(client)
              .to receive(:accept_merge_request)
              .exactly(8).times

            batch_merger.execute
          end

          it 'picks the merge requests targeting master into auto-deploy branch' do
            expect(cherry_picker)
              .to receive(:execute)
              .twice

            batch_merger.execute
          end

          it 'notifies the result' do
            expect(ReleaseTools::Slack::ChatopsNotification)
              .to receive(:security_issues_processed)

            batch_merger.execute
          end
        end

        context "with merge requests that couldn't be merged" do
          before do
            allow(issue_crawler)
              .to receive(:upcoming_security_issues_and_merge_requests)
              .and_return([issue1])

            allow(batch_merger)
              .to receive(:validated_merge_requests)
              .with(merge_requests)
              .and_return([[mr1, mr2, mr3, mr4], []])

            allow(issue_result.pending)
              .to receive(:key?)
              .and_return(true)

            mr_without_commit_sha = double(:merge_request, merge_commit_sha: nil)

            allow(client)
              .to receive(:accept_merge_request)
              .and_return(mr_without_commit_sha)
          end

          it 'does not pick the merge request targeting master to auto-deploy branch' do
            expect(issue_result)
              .to receive(:pending)
              .exactly(5).times

            expect(batch_merger)
              .not_to receive(:cherry_pick_into_auto_deploy)

            batch_merger.execute
          end

          it 'notifies the result' do
            expect(ReleaseTools::Slack::ChatopsNotification)
              .to receive(:security_issues_processed)

            batch_merger.execute
          end
        end
      end
    end
  end
end
