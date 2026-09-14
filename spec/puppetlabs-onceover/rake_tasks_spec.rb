require 'spec_helper'
require 'rake'
require 'ostruct'

describe 'rake_tasks.rb' do
  # SimpleCov/Coverage tracks a given file path's hit-lines against the ISeq
  # produced by the FIRST time it's compiled in this process. Re-`load`ing
  # the file fresh in a before(:each) (once per example) makes every example
  # after the first exercise a *new*, uninstrumented compilation, so real
  # task-body coverage silently reads back as 0. Instead we `load` the file
  # exactly once for the whole group, and use `Rake::Task#reenable` before
  # each invoke so a task can be invoked again in a later example.
  rake_tasks_path = File.expand_path('../../lib/puppetlabs-onceover/rake_tasks.rb', __dir__)
  Rake.application = Rake::Application.new
  load rake_tasks_path

  before(:each) do
    Rake::Task.tasks.each(&:reenable)
  end

  describe 'generate_fixtures' do
    it 'writes fixtures.yml when it does not already exist' do
      repo = double('repo', root: '/tmp/nonexistent_root_for_test', fixtures: "fixture_content")
      allow(PuppetlabsOnceover::Controlrepo).to receive(:new).and_return(repo)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.expand_path('./.fixtures.yml', repo.root)).and_return(false)
      allow(File).to receive(:write)

      Rake::Task['generate_fixtures'].invoke

      expect(File).to have_received(:write).with(File.expand_path('./.fixtures.yml', repo.root), 'fixture_content')
    end

    it 'raises when fixtures.yml already exists' do
      repo = double('repo', root: '/tmp/nonexistent_root_for_test')
      allow(PuppetlabsOnceover::Controlrepo).to receive(:new).and_return(repo)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.expand_path('./.fixtures.yml', repo.root)).and_return(true)

      expect { Rake::Task['generate_fixtures'].invoke }.to raise_error(/already exits/)
    end
  end

  describe 'hiera_setup' do
    it 'updates the datadir for hash values containing datadir and writes the new config' do
      hiera_config = { defaults: { datadir: 'orig/data' } }
      repo = double('repo')
      allow(repo).to receive(:hiera_config).and_return(hiera_config)
      # Use File.expand_path so these are real OS-native absolute paths on any
      # platform (Windows Pathname#relative_path_from raises "different prefix"
      # when comparing a bare '/some/repo'-style path against one that's been
      # expanded to a drive-letter path).
      allow(repo).to receive(:hiera_config_file).and_return(File.expand_path('/some/repo/hiera.yaml'))
      allow(repo).to receive(:hiera_data).and_return(File.expand_path('/some/repo/data'))
      allow(repo).to receive(:hiera_config=)
      allow(PuppetlabsOnceover::Controlrepo).to receive(:new).and_return(repo)

      Rake::Task['hiera_setup'].invoke

      expect(repo).to have_received(:hiera_config=) do |new_config|
        expect(new_config[:defaults][:datadir]).to eq('data')
      end
    end

    it 'leaves non-hash values alone' do
      hiera_config = { version: 5 }
      repo = double('repo')
      allow(repo).to receive(:hiera_config).and_return(hiera_config)
      allow(repo).to receive(:hiera_config_file).and_return('/some/repo/hiera.yaml')
      allow(repo).to receive(:hiera_data).and_return('/some/repo/data')
      allow(repo).to receive(:hiera_config=)
      allow(PuppetlabsOnceover::Controlrepo).to receive(:new).and_return(repo)

      Rake::Task['hiera_setup'].invoke

      expect(repo).to have_received(:hiera_config=).with(hiera_config)
    end
  end

  describe 'controlrepo_details' do
    it 'prints the controlrepo to_s' do
      repo = double('repo', to_s: 'REPO DETAILS')
      allow(PuppetlabsOnceover::Controlrepo).to receive(:new).and_return(repo)

      expect { Rake::Task['controlrepo_details'].invoke }.to output(/REPO DETAILS/).to_stdout
    end
  end

  describe 'generate_onceover_yaml' do
    it 'reads the controlrepo and renders the controlrepo.yaml.erb template' do
      repo = double('repo', roles: %w[role::web role::db], facts_files: ['/some/repo/facts/centos7.json', '/some/repo/facts/Windows_Server-2019.json'])
      allow(PuppetlabsOnceover::Controlrepo).to receive(:new).and_return(repo)

      # ERB.new's legacy positional (safe_level, trim_mode) arguments were
      # removed in the bundled erb gem (6.0.7+, Ruby 4.0) -- rake_tasks.rb
      # used to pass them positionally, which raised ArgumentError on that
      # Ruby before this fix. Now that it's fixed (keyword trim_mode:), this
      # asserts the template actually renders real content from the repo
      # double, not just that it "reaches" the call.
      expect { Rake::Task['generate_onceover_yaml'].invoke }.to output(
        a_string_including('role::web', 'role::db', 'centos7', 'Windows_Server-2019', 'Windows_Server-2019')
      ).to_stdout
    end
  end

  describe 'generate_nodesets' do
    it 'writes a nodeset entry for each factset, handling a 404 box lookup' do
      repo = double('repo')
      allow(repo).to receive(:facts).and_return([{ 'os' => { 'family' => 'RedHat' } }])
      allow(repo).to receive(:facts_files).and_return(['/some/repo/facts/centos7.json'])
      allow(PuppetlabsOnceover::Controlrepo).to receive(:new).and_return(repo)

      require 'puppetlabs-onceover/beaker'
      allow(PuppetlabsOnceover::Beaker).to receive(:facts_to_vagrant_box).and_return('centos/7')
      allow(PuppetlabsOnceover::Beaker).to receive(:facts_to_platform).and_return('el-7-x86_64')

      http_double = double('http', use_ssl: true, 'use_ssl=': true)
      response = double('response', code: '404', body: '{}')
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:get).and_return(response)

      # This deprecated task (Beaker removed) has a second, deeper,
      # pre-existing bug beyond the ERB.new Ruby-4.0 incompatibility fixed
      # elsewhere: nodeset.yaml.erb expects a `hosts_hash` local (and a
      # `prefix` local) that the task body never actually defines -- it
      # builds flat locals (node_name/boxname/platform/url/comment_out)
      # instead. Out of scope to redesign a deprecated task here; asserting
      # the real resulting error (and that execution reaches it, covering
      # the "HOSTS:" header and 404 branch first) rather than the old,
      # now-fixed ArgumentError.
      expect { Rake::Task['generate_nodesets'].invoke }.to raise_error(NameError, /hosts_hash/).and output(/HOSTS:/).to_stdout
    end

    it 'writes a nodeset entry using the virtualbox provider url when the box lookup succeeds' do
      repo = double('repo')
      allow(repo).to receive(:facts).and_return([{ 'os' => { 'family' => 'RedHat' } }])
      allow(repo).to receive(:facts_files).and_return(['/some/repo/facts/centos7.json'])
      allow(PuppetlabsOnceover::Controlrepo).to receive(:new).and_return(repo)

      require 'puppetlabs-onceover/beaker'
      allow(PuppetlabsOnceover::Beaker).to receive(:facts_to_vagrant_box).and_return('centos/7')
      allow(PuppetlabsOnceover::Beaker).to receive(:facts_to_platform).and_return('el-7-x86_64')

      box_body = {
        'current_version' => {
          'providers' => [
            { 'name' => 'virtualbox', 'original_url' => 'https://example.com/box.box' }
          ]
        }
      }.to_json

      http_double = double('http', use_ssl: true, 'use_ssl=': true)
      response = double('response', code: '200', body: box_body)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:get).and_return(response)

      # As above: covers the successful (non-404) lookup branch, including
      # the virtualbox provider url extraction, before hitting the same
      # pre-existing hosts_hash/prefix bug described above.
      expect { Rake::Task['generate_nodesets'].invoke }.to raise_error(NameError, /hosts_hash/).and output(/HOSTS:/).to_stdout
    end
  end

  describe 'generate_vendor_cache' do
    it 'creates a VendoredModules cache for the controlrepo' do
      repo = double('repo', spec_dir: '/some/repo/spec')
      allow(PuppetlabsOnceover::Controlrepo).to receive(:new).with(debug: true).and_return(repo)

      require 'puppetlabs-onceover/vendored_modules'
      allow(PuppetlabsOnceover::VendoredModules).to receive(:new)

      Rake::Task['generate_vendor_cache'].invoke

      expect(PuppetlabsOnceover::VendoredModules).to have_received(:new).with(
        hash_including(repo: repo, force_update: true)
      )
    end
  end
end
