# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::CherryPick::Service do
  let(:version) { ReleaseTools::Version.new('11.4.0-rc8') }
  let(:target) do
    double(
      branch_name: 'branch-name',
      exists?: true,
      project: ReleaseTools::Project::GitlabCe
    )
  end

  subject do
    described_class.new(target.project, version, target)
  end

  describe 'initialize' do
    it 'validates version argument' do
      version = double(valid?: false)

      expect { described_class.new(double, version, target) }
        .to raise_error(RuntimeError, /Invalid version provided/)
    end

    it 'validates target exists' do
      target = double(exists?: false)

      expect { described_class.new(double, version, target) }
        .to raise_error(RuntimeError, /Invalid cherry-pick target provided/)
    end
  end

  describe '#execute', vcr: { cassette_name: 'cherry_pick/with_prep_mr' } do
    context 'with no pickable MRs' do
      it 'does nothing' do
        expect(subject).to receive(:pickable_mrs).and_return([])

        expect(subject.execute).to eq([])
      end
    end

    context 'with pickable MRs' do
      def stub_picking
        # If the `merge_commit_sha` contains `failure`, we raise an error to
        # simulate a failed pick; otherwise return true
        allow(internal_client).to receive(:cherry_pick) do |_, keywords|
          if keywords[:ref].start_with?('failure')
            raise gitlab_error(:BadRequest, code: 400)
          else
            true
          end
        end
      end

      let(:notifier) { spy }
      let(:internal_client) { spy }
      let(:picks) do
        Gitlab::PaginatedResponse.new(
          [
            double(iid: 1, project_id: 13_083, merge_commit_sha: 'success-a').as_null_object,
            double(iid: 2, project_id: 13_083, merge_commit_sha: 'success-b').as_null_object,

            double(iid: 3, project_id: 13_083, merge_commit_sha: 'failure-a').as_null_object,
            double(iid: 4, project_id: 13_083, merge_commit_sha: 'failure-b').as_null_object,
            double(iid: 5, project_id: 13_083, merge_commit_sha: 'failure-c').as_null_object,
          ]
        )
      end

      before do
        allow(subject).to receive(:notifier).and_return(notifier)
        allow(subject).to receive(:client).and_return(internal_client)
        allow(subject).to receive(:pickable_mrs).and_return(picks)
      end

      it 'attempts to cherry pick each merge request' do
        expect(internal_client).to receive(:cherry_pick).exactly(5).times

        # Unset the `TEST` environment so we call the stubbed `cherry_pick`
        without_dry_run do
          subject.execute
        end
      end

      it 'posts a comment to each merge request' do
        stub_picking

        subject.execute

        expect(notifier).to have_received(:comment).exactly(5).times
      end

      it 'posts a summary comment to the preparation MR' do
        stub_picking

        subject.execute

        expect(notifier).to have_received(:summary)
      end

      it 'posts a blog post summary comment' do
        stub_picking

        subject.execute

        expect(notifier).to have_received(:blog_post_summary)
      end

      it 'cancels redundant pipelines' do
        ClimateControl.modify(FEATURE_CANCEL_REDUNDANT: 'true') do
          without_dry_run do
            subject.execute
          end
        end

        expect(internal_client)
          .to have_received(:cancel_redundant_pipelines)
          .with(target.project, ref: target.branch_name)
      end

      context 'when picking for auto-deploy' do
        let(:version) do
          ReleaseTools::AutoDeploy::Version
            .from_branch('12-5-auto-deploy-20191110')
            .to_ee
        end

        let(:target) do
          double(
            branch_name: version.auto_deploy_branch.branch_name,
            exists?: true,
            project: ReleaseTools::Project::GitlabEe
          )
        end

        let(:picks) do
          Gitlab::PaginatedResponse.new(
            [
              double(iid: 1, project_id: 13_083, merge_commit_sha: 'success-a', labels: %w[S1 bug]).as_null_object,
              double(iid: 2, project_id: 13_083, merge_commit_sha: 'success-b', labels: %w[S2]).as_null_object,
              double(iid: 3, project_id: 13_083, merge_commit_sha: 'success-c', labels: []).as_null_object,

              double(iid: 4, project_id: 13_083, merge_commit_sha: 'failure-a', labels: %w[P3]).as_null_object,
              double(iid: 5, project_id: 13_083, merge_commit_sha: 'failure-b', labels: %w[P1 S1]).as_null_object,
              double(iid: 6, project_id: 13_083, merge_commit_sha: 'failure-c', labels: []).as_null_object,
            ]
          )
        end

        it 'attempts to cherry pick only S1 and S2 merge requests' do
          stub_picking

          expect(internal_client).to receive(:cherry_pick).exactly(3).times

          without_dry_run do
            results = subject.execute

            success = results.select(&:success?)
            expect(success.size).to be(2)
            expect(success[0].merge_request.iid).to eql(picks[0].iid)
            expect(success[1].merge_request.iid).to eql(picks[1].iid)
            denied = results.select(&:denied?)
            expect(denied.size).to be(3)
            expect(denied.map(&:reason).uniq).to eq(['Merge request does not have S1 or S2 label'])
            expect(results.select(&:failure?).size).to be(4)
          end
        end
      end
    end
  end
end
