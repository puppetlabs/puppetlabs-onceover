require 'spec_helper'
require 'puppetlabs-onceover/controlrepo'
require 'r10k/puppetfile'
require 'tmpdir'
require 'fileutils'
require 'yaml'

describe "PuppetlabsOnceover::Controlrepo" do
  # TestConfig.new (used by #spec_tests) instantiates PuppetlabsOnceover::Class/Node/Group/Test,
  # each of which keep a process-global @@all array. Reset them around every example here too,
  # so this file doesn't leak state into (or pick up state from) other spec files' examples.
  before(:each) do
    PuppetlabsOnceover::Class.class_variable_set(:@@all, []) if defined?(PuppetlabsOnceover::Class)
    PuppetlabsOnceover::Node.class_variable_set(:@@all, []) if defined?(PuppetlabsOnceover::Node)
    PuppetlabsOnceover::Group.class_variable_set(:@@all, []) if defined?(PuppetlabsOnceover::Group)
    PuppetlabsOnceover::Test.class_variable_set(:@@all, []) if defined?(PuppetlabsOnceover::Test)
  end

  let(:basic_path) { File.expand_path('spec/fixtures/controlrepos/basic') }
  let(:minimal_path) { File.expand_path('spec/fixtures/controlrepos/minimal') }
  let(:factsets_path) { File.expand_path('spec/fixtures/controlrepos/factsets') }

  context "in a barebones controlrepo" do
    before do
      @repo = PuppetlabsOnceover::Controlrepo.new(path: minimal_path)
    end

    context "without hiera.yaml" do
      it { expect(@repo.hiera_config_file_relative_path).to be_nil }
      it { expect(@repo.hiera_config_file).to be_nil }
      it { expect(@repo.hiera_config).to be_nil }
    end
  end

  describe "#initialize" do
    it "uses the given :path directly" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
      expect(repo.root).to eq(basic_path)
    end

    it "traverses upward from Dir.pwd looking for environment.conf when no :path is given" do
      nested = File.join(basic_path, 'site', 'role', 'manifests')
      Dir.chdir(nested) do
        repo = PuppetlabsOnceover::Controlrepo.new
        expect(repo.root).to eq(basic_path)
      end
    end

    it "throws if it can never find an environment.conf above the cwd" do
      Dir.mktmpdir do |tmp|
        Dir.chdir(tmp) do
          # `throw "..."` with a String label (not caught anywhere) surfaces as an
          # UncaughtThrowError -- this is the real behavior of Controlrepo#initialize,
          # not a mistake in this spec.
          expect { PuppetlabsOnceover::Controlrepo.new }.to raise_error(UncaughtThrowError)
        end
      end
    end

    it "merges options found in an onceover.yaml when present" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: File.expand_path('spec/fixtures/controlrepos/function_mocking'))
      expect(repo.opts[:debug]).to eq(true)
    end

    it "sets the logger level to debug when :debug option is truthy" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path, debug: true)
      expect(repo.opts[:debug]).to eq(true)
    end

    it "expands a relative :manifest option against root" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path, manifest: 'site/role/manifests/example.pp')
      expect(repo.manifest).to eq(File.expand_path('site/role/manifests/example.pp', basic_path))
    end

    it "leaves manifest nil when not set anywhere" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: minimal_path)
      expect(repo.manifest).to be_nil
    end

    it "respects the ONCEOVER_YAML env var" do
      custom_yaml = File.expand_path('spec/fixtures/controlrepos/function_mocking/spec/onceover.yaml')
      begin
        ENV['ONCEOVER_YAML'] = custom_yaml
        repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
        expect(repo.onceover_yaml).to eq(custom_yaml)
      ensure
        ENV.delete('ONCEOVER_YAML')
      end
    end

    it "accepts explicit :facts_files" do
      f = File.expand_path('spec/fixtures/controlrepos/factsets/spec/factsets/centos_with_env.json')
      repo = PuppetlabsOnceover::Controlrepo.new(path: factsets_path, facts_files: [f])
      expect(repo.facts_files).to eq([f])
    end

    it "accepts a custom :role_regex and :profile_regex" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path, role_regex: '^role::', profile_regex: '^profile::')
      expect(repo.role_regex).to eq(/^role::/)
      expect(repo.profile_regex).to eq(/^profile::/)
    end
  end

  describe "class-level delegation methods" do
    before do
      @repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
    end

    it "delegates .root" do
      expect(PuppetlabsOnceover::Controlrepo.root).to eq(@repo.root)
    end

    it "delegates .puppetfile" do
      expect(PuppetlabsOnceover::Controlrepo.puppetfile).to eq(@repo.puppetfile)
    end

    it "delegates .facts_files" do
      expect(PuppetlabsOnceover::Controlrepo.facts_files).to eq(@repo.facts_files)
    end

    it "delegates .classes" do
      expect(PuppetlabsOnceover::Controlrepo.classes).to eq(@repo.classes)
    end

    it "delegates .roles" do
      expect(PuppetlabsOnceover::Controlrepo.roles).to eq(@repo.roles)
    end

    it "delegates .profiles" do
      expect(PuppetlabsOnceover::Controlrepo.profiles).to eq(@repo.profiles)
    end

    it "delegates .config" do
      expect(PuppetlabsOnceover::Controlrepo.config).to eq(@repo.config)
    end

    it "delegates .facts" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: factsets_path)
      expect(PuppetlabsOnceover::Controlrepo.facts).to eq(repo.facts(nil, 'values'))
    end

    it "delegates .trusted_facts" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: factsets_path)
      expect(PuppetlabsOnceover::Controlrepo.trusted_facts).to eq(repo.facts(nil, 'trusted'))
    end

    it "delegates .trusted_external_facts" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: factsets_path)
      expect(PuppetlabsOnceover::Controlrepo.trusted_external_facts).to eq(repo.facts(nil, 'trusted_external'))
    end

    it "delegates .hiera_config_file" do
      expect(PuppetlabsOnceover::Controlrepo.hiera_config_file).to eq(@repo.hiera_config_file)
    end
  end

  describe "#to_s" do
    it "renders a human readable summary" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
      output = repo.to_s
      expect(output).to include('puppetfile')
      expect(output).to include('roles')
      expect(output).to include('profiles')
    end
  end

  describe "#roles and #profiles" do
    it "finds roles matching the default role_regex" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
      expect(repo.roles).to include('role::webserver', 'role::database_server', 'role::example')
    end

    it "finds profiles matching the default profile_regex" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
      expect(repo.profiles).to include('profile::example', 'profile::base')
    end
  end

  describe "#classes / private #get_classes / #find_classname" do
    it "removes interpolated ($) modulepath entries before scanning" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
      classes = repo.classes
      expect(classes).not_to be_empty
    end

    it "#find_classname returns nil for a file with no class definition" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'nope.pp')
        File.write(file, "# just a comment\n")
        expect(repo.send(:find_classname, file)).to be_nil
      end
    end

    it "#find_classname rescues ArgumentError from an invalid byte sequence and keeps scanning" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'bad_encoding.pp')
        # An invalid UTF-8 byte sequence makes `line =~ regex` raise ArgumentError.
        File.open(file, 'wb') { |f| f.write("# \xFF\xFE bad line\n") }
        expect { repo.send(:find_classname, file) }.not_to raise_error
        expect(repo.send(:find_classname, file)).to be_nil
      end
    end

    it "#find_classname supports namespaced classes" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
      Dir.mktmpdir do |dir|
        file = File.join(dir, 'ns.pp')
        File.write(file, "class role::deep::nested {\n}\n")
        expect(repo.send(:find_classname, file)).to eq('role::deep::nested')
      end
    end

    it "#get_classes finds classes recursively under a directory" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
      classes = repo.send(:get_classes, File.join(basic_path, 'site'))
      expect(classes).to include('role::webserver')
    end
  end

  describe "#facts" do
    let(:repo) { PuppetlabsOnceover::Controlrepo.new(path: factsets_path) }

    it "returns an array of fact hashes" do
      expect(repo.facts).to be_an(Array)
      expect(repo.facts).not_to be_empty
    end

    it "raises if filter is not a Hash" do
      expect { repo.facts('not-a-hash') }.to raise_error(RuntimeError, /Filter param must be a hash/)
    end

    it "filters facts by a matching top-level key/value" do
      all = repo.facts
      sample = all.first
      key, value = sample.first
      filtered = repo.facts({ key => value })
      expect(filtered).not_to be_empty
    end

    it "returns an empty array when the filter matches nothing" do
      filtered = repo.facts({ 'this_key_does_not_exist_anywhere' => 'nope' })
      expect(filtered).to eq([])
    end

    it "supports nested hash filters via #keypair_is_in_hash" do
      expect(repo.send(:keypair_is_in_hash, { 'a' => { 'b' => 'c' } }, 'a', { 'b' => 'c' })).to eq(true)
      expect(repo.send(:keypair_is_in_hash, { 'a' => { 'b' => 'c' } }, 'a', { 'b' => 'nope' })).to eq(false)
      expect(repo.send(:keypair_is_in_hash, {}, 'missing', 'value')).to eq(false)
    end

    it "falls back to trusted/trusted_external top level keys when 'values' key is absent" do
      repo2 = PuppetlabsOnceover::Controlrepo.new(path: factsets_path)
      expect { repo2.facts(nil, 'trusted') }.not_to raise_error
    end
  end

  describe "#read_facts (private)" do
    let(:repo) { PuppetlabsOnceover::Controlrepo.new(path: factsets_path) }

    it "parses valid JSON" do
      f = Dir[File.join(factsets_path, 'spec', 'factsets', '*.json')].first
      expect(repo.send(:read_facts, f)).to be_a(Hash)
    end

    it "raises a friendly error for invalid JSON" do
      Dir.mktmpdir do |dir|
        bad = File.join(dir, 'bad.json')
        File.write(bad, "{not json")
        expect { repo.send(:read_facts, bad) }.to raise_error(RuntimeError, /Could not parse/)
      end
    end
  end

  describe "#config" do
    it "parses modulepath, strips comments, and handles values containing '='" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
      config = repo.config
      expect(config['modulepath']).to eq(['site', 'modules', '$basemodulepath'])
      expect(config['value_with_equals']).to eq("'foo=bar'")
    end

    it "raises a friendly error when modulepath is missing from environment.conf" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'environment.conf'), "config_version = 'x'\n")
        expect { PuppetlabsOnceover::Controlrepo.new(path: dir) }.to raise_error(RuntimeError, /modulepath was not found/)
      end
    end
  end

  describe "#hiera_config_file / #hiera_config_file_relative_path / #hiera_config / #hiera_config=" do
    it "prefers hiera.yaml in spec_dir over root" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'spec'))
        File.write(File.join(dir, 'environment.conf'), "modulepath = site:modules\n")
        File.write(File.join(dir, 'spec', 'hiera.yaml'), "---\nversion: 5\n")
        File.write(File.join(dir, 'hiera.yaml'), "---\nversion: 3\n")
        repo = PuppetlabsOnceover::Controlrepo.new(path: dir)
        expect(repo.hiera_config_file).to eq(File.expand_path('spec/hiera.yaml', dir))
        expect(repo.hiera_config['version']).to eq(5)
        expect(repo.hiera_config_file_relative_path).to eq('spec/hiera.yaml')
      end
    end

    it "falls back to hiera.yaml at root when not present in spec_dir" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'spec'))
        File.write(File.join(dir, 'environment.conf'), "modulepath = site:modules\n")
        File.write(File.join(dir, 'hiera.yaml'), "---\nversion: 3\n")
        repo = PuppetlabsOnceover::Controlrepo.new(path: dir)
        expect(repo.hiera_config_file).to eq(File.expand_path('hiera.yaml', dir))
        expect(repo.hiera_config['version']).to eq(3)
      end
    end

    it "returns nil from #hiera_config and prints a warning when no hiera.yaml exists anywhere" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: minimal_path)
      expect { expect(repo.hiera_config).to be_nil }.to output(/WARNING: Could not find hiera config file/).to_stdout
    end

    it "#hiera_config= writes the given data back to hiera_config_file" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'spec'))
        File.write(File.join(dir, 'environment.conf'), "modulepath = site:modules\n")
        File.write(File.join(dir, 'spec', 'hiera.yaml'), "---\nversion: 5\n")
        repo = PuppetlabsOnceover::Controlrepo.new(path: dir)
        repo.hiera_config = { 'version' => 5, 'defaults' => { 'datadir' => 'newdata' } }
        expect(YAML.load_file(repo.hiera_config_file)['defaults']['datadir']).to eq('newdata')
      end
    end
  end

  describe "#hiera_data" do
    it "finds a single hiera-ish data directory" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'environment.conf'), "modulepath = site:modules\n")
        FileUtils.mkdir_p(File.join(dir, 'hieradata'))
        repo = PuppetlabsOnceover::Controlrepo.new(path: dir)
        expect(repo.hiera_data).to eq(File.expand_path('hieradata', dir))
      end
    end

    it "raises when there is more than one candidate hiera data directory" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'environment.conf'), "modulepath = site:modules\n")
        FileUtils.mkdir_p(File.join(dir, 'hieradata'))
        FileUtils.mkdir_p(File.join(dir, 'hiera_data_2'))
        repo = PuppetlabsOnceover::Controlrepo.new(path: dir)
        expect { repo.hiera_data }.to raise_error(RuntimeError, /too many directories/)
      end
    end
  end

  describe "#r10k_config_file / #r10k_config / #r10k_config=" do
    it "prefers r10k.yaml in spec_dir over root" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'spec'))
        File.write(File.join(dir, 'environment.conf'), "modulepath = site:modules\n")
        File.write(File.join(dir, 'spec', 'r10k.yaml'), "---\ncachedir: /tmp/spec-cache\n")
        File.write(File.join(dir, 'r10k.yaml'), "---\ncachedir: /tmp/root-cache\n")
        repo = PuppetlabsOnceover::Controlrepo.new(path: dir)
        expect(repo.r10k_config_file).to eq(File.expand_path('spec/r10k.yaml', dir))
        expect(repo.r10k_config['cachedir']).to eq('/tmp/spec-cache')
      end
    end

    it "falls back to r10k.yaml at root" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'spec'))
        File.write(File.join(dir, 'environment.conf'), "modulepath = site:modules\n")
        File.write(File.join(dir, 'r10k.yaml'), "---\ncachedir: /tmp/root-cache\n")
        repo = PuppetlabsOnceover::Controlrepo.new(path: dir)
        expect(repo.r10k_config_file).to eq(File.expand_path('r10k.yaml', dir))
      end
    end

    it "returns nil when neither exists" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: minimal_path)
      expect(repo.r10k_config_file).to be_nil
    end

    it "#r10k_config= writes data back out" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'spec'))
        File.write(File.join(dir, 'environment.conf'), "modulepath = site:modules\n")
        File.write(File.join(dir, 'spec', 'r10k.yaml'), "---\ncachedir: /tmp/a\n")
        repo = PuppetlabsOnceover::Controlrepo.new(path: dir)
        repo.r10k_config = { 'cachedir' => '/tmp/b' }
        expect(YAML.load_file(repo.r10k_config_file)['cachedir']).to eq('/tmp/b')
      end
    end
  end

  describe "#temp_manifest" do
    it "returns whatever @manifest currently is" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path, manifest: 'site/role/manifests/example.pp')
      expect(repo.temp_manifest).to eq(repo.manifest)
    end
  end

  describe "#print_puppetfile_table" do
    it "prints a table for both forge and git modules, out-of-date and up-to-date" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)

      puppetfile = R10K::Puppetfile.new(basic_path)
      puppetfile.load!
      forge_mod = puppetfile.modules.find { |m| m.is_a?(R10K::Module::Forge) }
      git_mod   = puppetfile.modules.find { |m| m.is_a?(R10K::Module::Git) }

      current_release = double('release', version: '9.9.9')
      v3_module = double('v3_module', current_release: current_release, endorsement: 'supported', superseded_by: nil)
      allow(forge_mod).to receive(:v3_module).and_return(v3_module)

      allow(R10K::Puppetfile).to receive(:new).and_return(puppetfile)
      allow(puppetfile).to receive(:load!)

      expect { repo.print_puppetfile_table }.to output(/Full Name/).to_stdout
    end

    it "captures a RuntimeError raised while assessing a module and reports it in the error table" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)

      puppetfile = R10K::Puppetfile.new(basic_path)
      puppetfile.load!
      forge_mod = puppetfile.modules.find { |m| m.is_a?(R10K::Module::Forge) }

      call_count = 0
      allow(forge_mod).to receive(:v3_module) do
        call_count += 1
        if call_count == 1
          raise RuntimeError, 'boom'
        else
          double('v3_module', current_release: double('release', version: '4.11.0'))
        end
      end
      allow(forge_mod).to receive(:expected_version).and_return('4.11.0')

      allow(R10K::Puppetfile).to receive(:new).and_return(puppetfile)
      allow(puppetfile).to receive(:load!)
      allow(puppetfile).to receive(:modules).and_return([forge_mod])

      expect { repo.print_puppetfile_table }.to output(/Issue assessing module/).to_stdout
    end

    it "marks major/minor/tiny/patchlevel version differences appropriately" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
      puppetfile = R10K::Puppetfile.new(basic_path)
      puppetfile.load!
      forge_mod = puppetfile.modules.find { |m| m.is_a?(R10K::Module::Forge) }
      allow(forge_mod).to receive(:expected_version).and_return('1.0.0')
      current_release = double('release', version: '2.0.0')
      v3_module = double('v3_module', current_release: current_release, endorsement: 'supported', superseded_by: { slug: 'newmod' })
      allow(forge_mod).to receive(:v3_module).and_return(v3_module)

      allow(R10K::Puppetfile).to receive(:new).and_return(puppetfile)
      allow(puppetfile).to receive(:load!)
      allow(puppetfile).to receive(:modules).and_return([forge_mod])

      expect { repo.print_puppetfile_table }.to output(/Major/).to_stdout
    end

    it "marks a minor version difference" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
      puppetfile = R10K::Puppetfile.new(basic_path)
      puppetfile.load!
      forge_mod = puppetfile.modules.find { |m| m.is_a?(R10K::Module::Forge) }
      allow(forge_mod).to receive(:expected_version).and_return('1.0.0')
      v3_module = double('v3_module', current_release: double('release', version: '1.1.0'), endorsement: 'supported', superseded_by: nil)
      allow(forge_mod).to receive(:v3_module).and_return(v3_module)
      allow(R10K::Puppetfile).to receive(:new).and_return(puppetfile)
      allow(puppetfile).to receive(:load!)
      allow(puppetfile).to receive(:modules).and_return([forge_mod])
      expect { repo.print_puppetfile_table }.to output(/Minor/).to_stdout
    end

    it "marks a tiny version difference" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
      puppetfile = R10K::Puppetfile.new(basic_path)
      puppetfile.load!
      forge_mod = puppetfile.modules.find { |m| m.is_a?(R10K::Module::Forge) }
      allow(forge_mod).to receive(:expected_version).and_return('1.0.0')
      v3_module = double('v3_module', current_release: double('release', version: '1.0.1'), endorsement: 'supported', superseded_by: nil)
      allow(forge_mod).to receive(:v3_module).and_return(v3_module)
      allow(R10K::Puppetfile).to receive(:new).and_return(puppetfile)
      allow(puppetfile).to receive(:load!)
      allow(puppetfile).to receive(:modules).and_return([forge_mod])
      expect { repo.print_puppetfile_table }.to output(/Tiny/).to_stdout
    end

    it "marks a patchlevel version difference" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
      puppetfile = R10K::Puppetfile.new(basic_path)
      puppetfile.load!
      forge_mod = puppetfile.modules.find { |m| m.is_a?(R10K::Module::Forge) }
      allow(forge_mod).to receive(:expected_version).and_return('1.0.0-0')
      v3_module = double('v3_module', current_release: double('release', version: '1.0.0-1'), endorsement: 'supported', superseded_by: nil)
      allow(forge_mod).to receive(:v3_module).and_return(v3_module)
      allow(R10K::Puppetfile).to receive(:new).and_return(puppetfile)
      allow(puppetfile).to receive(:load!)
      allow(puppetfile).to receive(:modules).and_return([forge_mod])
      expect { repo.print_puppetfile_table }.to output(/PatchLevel/).to_stdout
    end

    it "marks a patchlevel_minor version difference" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
      puppetfile = R10K::Puppetfile.new(basic_path)
      puppetfile.load!
      forge_mod = puppetfile.modules.find { |m| m.is_a?(R10K::Module::Forge) }
      allow(forge_mod).to receive(:expected_version).and_return('1.0.0-0-0')
      v3_module = double('v3_module', current_release: double('release', version: '1.0.0-0-1'), endorsement: 'supported', superseded_by: nil)
      allow(forge_mod).to receive(:v3_module).and_return(v3_module)
      allow(R10K::Puppetfile).to receive(:new).and_return(puppetfile)
      allow(puppetfile).to receive(:load!)
      allow(puppetfile).to receive(:modules).and_return([forge_mod])
      expect { repo.print_puppetfile_table }.to output(/PatchLevel_minor/).to_stdout
    end

    it "marks 'No' when versions are identical" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
      puppetfile = R10K::Puppetfile.new(basic_path)
      puppetfile.load!
      forge_mod = puppetfile.modules.find { |m| m.is_a?(R10K::Module::Forge) }
      allow(forge_mod).to receive(:expected_version).and_return('1.0.0')
      v3_module = double('v3_module', current_release: double('release', version: '1.0.0'), endorsement: 'supported', superseded_by: nil)
      allow(forge_mod).to receive(:v3_module).and_return(v3_module)
      allow(R10K::Puppetfile).to receive(:new).and_return(puppetfile)
      allow(puppetfile).to receive(:load!)
      allow(puppetfile).to receive(:modules).and_return([forge_mod])
      expect { repo.print_puppetfile_table }.to output(/No/).to_stdout
    end
  end

  describe "#update_puppetfile" do
    it "rewrites the expected version of forge modules in place" do
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(Dir.glob(File.join(basic_path, '*')), dir)
        repo = PuppetlabsOnceover::Controlrepo.new(path: dir)

        puppetfile = R10K::Puppetfile.new(dir)
        puppetfile.load!
        forge_mod = puppetfile.modules.find { |m| m.is_a?(R10K::Module::Forge) }
        allow(forge_mod).to receive(:owner).and_return('puppetlabs')
        allow(forge_mod).to receive(:name).and_return('stdlib')
        allow(forge_mod).to receive(:expected_version).and_return('4.11.0')
        v3_module = double('v3_module', current_release: double('release', version: '9.9.9'))
        allow(forge_mod).to receive(:v3_module).and_return(v3_module)
        allow(puppetfile).to receive(:modules).and_return([forge_mod])

        allow(R10K::Puppetfile).to receive(:new).and_return(puppetfile)
        allow(puppetfile).to receive(:load!)

        expect { repo.update_puppetfile }.to output(/changed/).to_stdout
        expect(File.read(repo.puppetfile)).to include('9.9.9')
      end
    end
  end

  describe "#fixtures" do
    it "renders a .fixtures.yml with symlinks, forge_modules and repositories" do
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(Dir.glob(File.join(basic_path, '*')), dir)
        repo = PuppetlabsOnceover::Controlrepo.new(path: dir)

        puppetfile = R10K::Puppetfile.new(dir)
        puppetfile.load!

        allow(R10K::Puppetfile).to receive(:new).and_return(puppetfile)
        allow(puppetfile).to receive(:load).and_return(true)

        # The `code_dirs.each { |dir| Dir["#{dir}/*"] }` loop in #fixtures uses the
        # modulepath entries as-is (unexpanded, unlike #classes), so it only finds
        # anything when the process cwd is the controlrepo root.
        result = nil
        Dir.chdir(dir) { result = repo.fixtures }
        expect(result).to include('forge_modules')
        expect(result).to include('repositories')
        expect(result).to include('symlinks')
      end
    end

    it "treats a Hash expected_version (local path) as a symlink" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'environment.conf'), "modulepath = site:modules:$basemodulepath\n")
        repo = PuppetlabsOnceover::Controlrepo.new(path: dir)

        local_mod = double('mod')
        allow(local_mod).to receive(:is_a?).with(R10K::Module::Forge).and_return(true)
        allow(local_mod).to receive(:is_a?).with(R10K::Module::Git).and_return(false)
        allow(local_mod).to receive(:to_s).and_return('localmod')
        allow(local_mod).to receive(:name).and_return('localmod')
        allow(local_mod).to receive(:expected_version).and_return({ path: '/some/local/path' })

        puppetfile = double('puppetfile', load: true, modules: [local_mod])
        allow(R10K::Puppetfile).to receive(:new).and_return(puppetfile)

        result = repo.fixtures
        expect(result).to include('symlinks')
        expect(result).to include('/some/local/path')
      end
    end

    it "raises if the Puppetfile cannot be loaded" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'environment.conf'), "modulepath = site:modules:$basemodulepath\n")
        repo = PuppetlabsOnceover::Controlrepo.new(path: dir)
        puppetfile = double('puppetfile', load: false)
        allow(R10K::Puppetfile).to receive(:new).and_return(puppetfile)
        expect { repo.fixtures }.to raise_error(RuntimeError, /Could not load Puppetfile/)
      end
    end
  end

  describe "self.evaluate_template" do
    after(:each) { PuppetlabsOnceover::Controlrepo.instance_variable_set(:@root, nil) }

    it "renders the gem's default template when no custom one is present" do
      repo = double('repo', roles: [], facts_files: [])
      result = PuppetlabsOnceover::Controlrepo.evaluate_template('controlrepo.yaml.erb', binding)
      expect(result).to include('classes:')
    end

    it "prefers a custom template under <root>/spec/templates when present" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'spec', 'templates'))
        File.write(File.join(dir, 'spec', 'templates', 'my_template.erb'), "custom-<%= 1 + 1 %>\n")
        PuppetlabsOnceover::Controlrepo.instance_variable_set(:@root, dir)

        result = nil
        expect { result = PuppetlabsOnceover::Controlrepo.evaluate_template('my_template.erb', binding) }.to output(/Using Custom/).to_stdout
        expect(result).to include('custom-2')
      end
    end
  end

  describe "self.create_dirs_and_log" do
    it "creates all missing intermediate directories and logs each one" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, 'a', 'b', 'c')
        Dir.chdir(dir) do
          expect { PuppetlabsOnceover::Controlrepo.create_dirs_and_log(target) }.to output(/created/).to_stdout
        end
        expect(File.directory?(target)).to eq(true)
      end
    end

    it "does nothing when the directory already exists" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          out = capture_stdout { PuppetlabsOnceover::Controlrepo.create_dirs_and_log(dir) }
          expect(out).to eq('')
        end
      end
    end
  end

  describe "self.init_write_file" do
    it "creates the file (and parent dirs) when it does not exist" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          target = File.join(dir, 'nested', 'file.txt')
          expect { PuppetlabsOnceover::Controlrepo.init_write_file('hello', target) }.to output(/created/).to_stdout
          expect(File.read(target)).to eq('hello')
        end
      end
    end

    it "skips writing when the file already exists" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          target = File.join(dir, 'file.txt')
          File.write(target, 'original')
          expect { PuppetlabsOnceover::Controlrepo.init_write_file('new content', target) }.to output(/skipped/).to_stdout
          expect(File.read(target)).to eq('original')
        end
      end
    end
  end

  describe "self.generate_onceover_yaml" do
    it "renders a controlrepo.yaml.erb driven by the repo's roles and facts_files" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: basic_path)
      result = PuppetlabsOnceover::Controlrepo.generate_onceover_yaml(repo)
      expect(result).to include('classes:')
      expect(result).to include('nodes:')
    end
  end

  describe "self.init" do
    it "writes out the standard set of config files and updates .gitignore" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'spec'))
        File.write(File.join(dir, 'environment.conf'), "modulepath = site:modules:$basemodulepath\n")
        repo = PuppetlabsOnceover::Controlrepo.new(path: dir)

        allow(Dir).to receive(:pwd).and_call_original

        Dir.chdir(dir) do
          expect { PuppetlabsOnceover::Controlrepo.init(repo) }.to output(/created/).to_stdout
        end

        expect(File.exist?(repo.onceover_yaml)).to eq(true)
        expect(File.exist?(File.join(dir, 'Rakefile'))).to eq(true)
        expect(File.exist?(File.join(dir, 'Gemfile'))).to eq(true)
        expect(File.read(File.join(dir, '.gitignore'))).to include('.onceover')
      end
    end

    it "appends to an existing .gitignore rather than clobbering it" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'spec'))
        File.write(File.join(dir, 'environment.conf'), "modulepath = site:modules:$basemodulepath\n")
        File.write(File.join(dir, '.gitignore'), "vendor/\n")
        repo = PuppetlabsOnceover::Controlrepo.new(path: dir)

        Dir.chdir(dir) do
          PuppetlabsOnceover::Controlrepo.init(repo)
        end

        content = File.read(File.join(dir, '.gitignore'))
        expect(content).to include('vendor/')
        expect(content).to include('.onceover')
      end
    end

    it "does not touch .gitignore again if .onceover is already listed" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, 'spec'))
        File.write(File.join(dir, 'environment.conf'), "modulepath = site:modules:$basemodulepath\n")
        File.write(File.join(dir, '.gitignore'), ".onceover\n")
        repo = PuppetlabsOnceover::Controlrepo.new(path: dir)

        Dir.chdir(dir) do
          out = capture_stdout { PuppetlabsOnceover::Controlrepo.init(repo) }
          expect(out).not_to match(/changed .gitignore/)
        end
      end
    end
  end

  describe "self.generate_nodesets (deprecated)" do
    it "comments out hosts for which no vagrant box could be found (404)" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: factsets_path)

      response = double('response', code: '404', body: nil)
      http = double('http')
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:get).and_return(response)
      allow(Net::HTTP).to receive(:new).and_return(http)

      result = PuppetlabsOnceover::Controlrepo.generate_nodesets(repo)
      expect(result).to include('HOSTS')
      expect(result).to include('#')
    end

    it "includes a real box url when the API call succeeds" do
      repo = PuppetlabsOnceover::Controlrepo.new(path: factsets_path)

      box_body = {
        'current_version' => {
          'providers' => [
            { 'name' => 'virtualbox', 'original_url' => 'https://example.com/box.box' }
          ]
        }
      }.to_json

      response = double('response', code: '200', body: box_body)
      http = double('http')
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:get).and_return(response)
      allow(Net::HTTP).to receive(:new).and_return(http)

      result = PuppetlabsOnceover::Controlrepo.generate_nodesets(repo)
      expect(result).to include('box_url')
      expect(result).to include('https://example.com/box.box')
    end
  end

  describe "#spec_tests" do
    it "yields deduplicated, filtered test tuples built from onceover.yaml" do
      repo_path = File.expand_path('spec/fixtures/controlrepos/function_mocking')
      repo = PuppetlabsOnceover::Controlrepo.new(path: repo_path, onceover_yaml: File.join(repo_path, 'spec', 'onceover.yaml'))

      yielded = []
      repo.spec_tests do |class_name, node_name, fact_set, trusted_set, trusted_external_set, pre_condition|
        yielded << [class_name, node_name]
      end

      expect(yielded).not_to be_empty
      expect(yielded.map(&:first)).to all(match(/role::/))
    end
  end
end

def capture_stdout
  old = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = old
end
