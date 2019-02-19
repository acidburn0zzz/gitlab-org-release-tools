RSpec.shared_examples 'helm-release #execute' do |expect_tag: true, expect_master: true|
  def execute(branch)
    release.execute
    repository.checkout(branch)
  end

  it 'performs changelog compilation' do
    allow(release).to receive(:bump_version).and_return true
    allow(release).to receive(:add_changelog).and_return true

    if expect_tag
      expect(changelog_manager).to receive(:release).with(ReleaseTools::HelmChartVersion.new(expected_chart_version))
    else
      expect(changelog_manager).not_to receive(:release)
    end

    execute(branch)
  end

  it 'creates a new branch and updates the version and appVersion in Chart.yaml, and a new tag' do
    allow(release).to receive(:add_changelog).and_return true
    expect(release).to receive(:bump_version).with(expected_chart_version, gitlab_version).once do
      original_chartfile = release.version_manager.method(:parse_chart_file)
      allow(release.version_manager).to receive(:parse_chart_file) do
        next original_chartfile.call unless repository.head.name == "refs/heads/#{branch}"
        instance_double(
          "ChartFile",
          version: expected_chart_version && ReleaseTools::HelmChartVersion.new(expected_chart_version),
          app_version: gitlab_version && ReleaseTools::HelmGitlabVersion.new(gitlab_version)
        )
      end
    end

    if expect_master
      expect(release).to receive(:bump_version).with(expected_chart_version).once
    else
      expect(release).not_to receive(:bump_version).with(expected_chart_version)
    end

    execute(branch)

    aggregate_failures do
      expect(repository.head.name).to eq "refs/heads/#{branch}"
      if expect_tag
        expect(repository.tags["v#{expected_chart_version}"]).not_to be_nil
      else
        expect(repository.tags["v#{expected_chart_version}"]).to be_nil
      end
    end
  end
end
