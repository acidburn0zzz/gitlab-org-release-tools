require 'spec_helper'
require 'project/gitlab_ee'

describe Project::GitlabEe do
  it_behaves_like 'project #remotes'

  describe '.path' do
    it { expect(described_class.path).to eq 'gitlab-org/gitlab-ee' }
  end

  describe '.group' do
    it { expect(described_class.group).to eq 'gitlab-org' }
  end
end
