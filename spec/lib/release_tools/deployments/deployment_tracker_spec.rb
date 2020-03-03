# frozen_string_literal: true

require 'spec_helper'

describe ReleaseTools::Deployments::DeploymentTracker do
  describe '#qa_commit_range' do
    let(:version) { '12.7.202001101501-94b8fd8d152.6fea3031ec9' }

    context 'when deploying failed' do
      it 'returns an empty Array' do
        tracker = described_class.new('gstg', 'failed', version)

        expect(tracker.qa_commit_range).to be_empty
      end
    end

    context 'when deploying to a QA environment with deployments' do
      it 'returns the current and previous deployment SHAs' do
        tracker = described_class.new('gstg', 'success', version)

        allow(ReleaseTools::GitlabClient)
          .to receive(:deployments)
          .and_return([
            double(:deployment, sha: 'bar'),
            double(:deployment, sha: 'foo')
          ])

        expect(tracker.qa_commit_range).to eq(%w[foo bar])
      end
    end

    context 'when deploying to a QA environment with for the first time' do
      it 'does not return the previous deployment SHA' do
        tracker = described_class.new('gstg', 'success', version)

        allow(ReleaseTools::GitlabClient)
          .to receive(:deployments)
          .and_return([double(:deployment, sha: 'foo')])

        expect(tracker.qa_commit_range).to eq([nil, 'foo'])
      end
    end

    context 'when deploying to a non-QA environment' do
      it 'returns an empty Array' do
        tracker = described_class.new('foo', 'success', version)

        allow(ReleaseTools::GitlabClient)
          .to receive(:deployments)
          .and_return([])

        expect(tracker.qa_commit_range).to be_empty
      end
    end
  end

  describe '#track' do
    context 'when using a valid status' do
      let(:version) { '12.7.202001101501-94b8fd8d152.6fea3031ec9' }
      let(:parser) do
        instance_double(ReleaseTools::Deployments::DeploymentVersionParser)
      end
      let(:omnibus_parser) do
        instance_double(ReleaseTools::Deployments::OmnibusDeploymentVersionParser)
      end

      let(:parsed_version) do
        ReleaseTools::Deployments::DeploymentVersionParser::DeploymentVersion
          .new('123', 'master', false)
      end

      let(:parsed_omnibus_version) do
        ReleaseTools::Deployments::OmnibusDeploymentVersionParser::DeploymentVersion
          .new('456', 'master', false)
      end

      before do
        allow(parser)
          .to receive(:parse)
          .with(version)
          .and_return(parsed_version)

        allow(ReleaseTools::Deployments::DeploymentVersionParser)
          .to receive(:new)
          .and_return(parser)

        allow(omnibus_parser)
          .to receive(:parse)
          .with(version)
          .and_return(parsed_omnibus_version)

        allow(ReleaseTools::Deployments::OmnibusDeploymentVersionParser)
          .to receive(:new)
          .and_return(omnibus_parser)
      end

      it 'tracks the deployment of GitLab, Gitaly, and Omnibus GitLab' do
        allow(ReleaseTools::GitlabClient)
          .to receive(:file_contents)
          .with(
            ReleaseTools::Project::GitlabEe,
            'GITALY_SERVER_VERSION',
            '123'
          )
          .and_return('94b8fd8d152680445ec14241f14d1e4c04b0b5ab')

        expect(ReleaseTools::GitlabClient)
          .to receive(:create_deployment)
          .with(
            ReleaseTools::Project::GitlabEe.canonical_or_security_path,
            'staging',
            'master',
            '123',
            'success',
            tag: false
          )
          .and_return(double(:deployment, id: 1, status: 'success'))

        expect(ReleaseTools::GitlabClient)
          .to receive(:create_deployment)
          .with(
            ReleaseTools::Project::Gitaly.canonical_or_security_path,
            'staging',
            'master',
            '94b8fd8d152680445ec14241f14d1e4c04b0b5ab',
            'success',
            tag: false
          )
          .and_return(double(:deployment, id: 2, status: 'success'))

        expect(ReleaseTools::GitlabClient)
          .to receive(:create_deployment)
          .with(
            ReleaseTools::Project::OmnibusGitlab.canonical_or_security_path,
            'staging',
            'master',
            '456',
            'success',
            tag: false
          )
          .and_return(double(:deployment, id: 3, status: 'success'))

        deployments = described_class.new('staging', 'success', version).track

        expect(deployments.length).to eq(3)
        expect(deployments[0].id).to eq(1)
        expect(deployments[1].id).to eq(2)
        expect(deployments[2].id).to eq(3)
      end

      it 'tracks the Gitaly deployment when Gitaly uses a tag version' do
        allow(ReleaseTools::GitlabClient)
          .to receive(:file_contents)
          .with(
            ReleaseTools::Project::GitlabEe,
            'GITALY_SERVER_VERSION',
            '123'
          )
          .and_return('1.2.3')

        expect(ReleaseTools::GitlabClient)
          .to receive(:create_deployment)
          .with(
            ReleaseTools::Project::GitlabEe.canonical_or_security_path,
            'staging',
            'master',
            '123',
            'success',
            tag: false
          )
          .and_return(double(:deployment, id: 1, status: 'success'))

        expect(ReleaseTools::GitlabClient)
          .to receive(:tag)
          .with(
            ReleaseTools::Project::Gitaly.canonical_or_security_path,
            tag: 'v1.2.3'
          )
          .and_return(
            double(:tag, name: 'v1.2.3', commit: double(:commit, id: 'abc'))
          )

        expect(ReleaseTools::GitlabClient)
          .to receive(:create_deployment)
          .with(
            ReleaseTools::Project::Gitaly.canonical_or_security_path,
            'staging',
            'v1.2.3',
            'abc',
            'success',
            tag: true
          )
          .and_return(double(:deployment, id: 2, status: 'success'))

        expect(ReleaseTools::GitlabClient)
          .to receive(:create_deployment)
          .with(
            ReleaseTools::Project::OmnibusGitlab.canonical_or_security_path,
            'staging',
            'master',
            '456',
            'success',
            tag: false
          )
          .and_return(double(:deployment, id: 3, status: 'success'))

        deployments = described_class.new('staging', 'success', version).track

        expect(deployments.length).to eq(3)
        expect(deployments[0].id).to eq(1)
        expect(deployments[1].id).to eq(2)
        expect(deployments[2].id).to eq(3)
      end

      it 'tracks the Gitaly deployment when Gitaly uses an RC tag version' do
        allow(ReleaseTools::GitlabClient)
          .to receive(:file_contents)
          .with(
            ReleaseTools::Project::GitlabEe,
            'GITALY_SERVER_VERSION',
            '123'
          )
          .and_return('1.2.3-rc1')

        expect(ReleaseTools::GitlabClient)
          .to receive(:create_deployment)
          .with(
            ReleaseTools::Project::GitlabEe.canonical_or_security_path,
            'staging',
            'master',
            '123',
            'success',
            tag: false
          )
          .and_return(double(:deployment, id: 1, status: 'success'))

        expect(ReleaseTools::GitlabClient)
          .to receive(:tag)
          .with(
            ReleaseTools::Project::Gitaly.canonical_or_security_path,
            tag: 'v1.2.3-rc1'
          )
          .and_return(
            double(:tag, name: 'v1.2.3-rc1', commit: double(:commit, id: 'abc'))
          )

        expect(ReleaseTools::GitlabClient)
          .to receive(:create_deployment)
          .with(
            ReleaseTools::Project::Gitaly.canonical_or_security_path,
            'staging',
            'v1.2.3-rc1',
            'abc',
            'success',
            tag: true
          )
          .and_return(double(:deployment, id: 2, status: 'success'))

        expect(ReleaseTools::GitlabClient)
          .to receive(:create_deployment)
          .with(
            ReleaseTools::Project::OmnibusGitlab.canonical_or_security_path,
            'staging',
            'master',
            '456',
            'success',
            tag: false
          )
          .and_return(double(:deployment, id: 3, status: 'success'))

        deployments = described_class.new('staging', 'success', version).track

        expect(deployments.length).to eq(3)
        expect(deployments[0].id).to eq(1)
        expect(deployments[1].id).to eq(2)
        expect(deployments[2].id).to eq(3)
      end
    end

    context 'when using an invalid status' do
      it 'raises ArgumentError' do
        version = '12.7.202001101501-94b8fd8d152.6fea3031ec9'

        expect { described_class.new('staging', 'foo', version).track }
          .to raise_error(ArgumentError)
      end
    end
  end
end
