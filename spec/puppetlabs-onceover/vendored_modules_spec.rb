require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'multi_json'
require 'net/http'
require 'puppetlabs-onceover/controlrepo' # pulls in `include PuppetlabsOnceover::Logger` at top-level
require 'puppetlabs-onceover/vendored_modules'

describe PuppetlabsOnceover::VendoredModules do
  let(:tempdir)     { Dir.mktmpdir }
  let(:spec_dir)    { Dir.mktmpdir }
  let(:repo_double) { double('repo', tempdir: tempdir, spec_dir: spec_dir) }
  let(:puppet_version) { Puppet.version }
  let(:core_modules) { described_class::CORE_MODULES }

  def populate_cache(cachedir, mods: core_modules, version: puppet_version, tag: 'v1.2.3')
    FileUtils.mkdir_p(cachedir)
    mods.each do |mod|
      File.write(File.join(cachedir, "#{mod}-puppet_agent-#{version}.json"), MultiJson.dump([{ 'name' => tag }]))
    end
  end

  after do
    FileUtils.remove_entry(tempdir) if File.exist?(tempdir)
    FileUtils.remove_entry(spec_dir) if File.exist?(spec_dir)
  end

  describe '#initialize' do
    context 'when the cache is already populated (cache-hit branch, no network access)' do
      before { populate_cache(File.join(tempdir, 'vendored_modules')) }

      subject(:vm) { described_class.new(repo: repo_double) }

      it 'resolves a vendored reference for every core module' do
        expect(vm.vendored_references.size).to eq(core_modules.size)
      end

      it 'builds the url and ref from the cached tag' do
        ref = vm.vendored_references.first
        expect(ref['url']).to eq("https://github.com/puppetlabs/puppetlabs-#{core_modules.first}.git")
        expect(ref['ref']).to eq('refs/tags/v1.2.3')
      end

      it 'starts with an empty missing_vendored list' do
        expect(vm.missing_vendored).to eq([])
      end
    end

    context 'when the cachedir does not exist yet' do
      it 'creates it via FileUtils.mkdir_p' do
        cachedir = File.join(tempdir, 'vendored_modules')
        expect(File.directory?(cachedir)).to be false
        allow_any_instance_of(described_class).to receive(:github_get).and_return([{ 'name' => 'v9.9.9' }])
        described_class.new(repo: repo_double)
        expect(File.directory?(cachedir)).to be true
      end
    end

    context 'when opts[:cachedir] is explicitly provided' do
      it 'uses it instead of the repo tempdir default' do
        custom_cachedir = Dir.mktmpdir
        populate_cache(custom_cachedir)
        vm = described_class.new(repo: repo_double, cachedir: custom_cachedir)
        expect(vm.vendored_references.size).to eq(core_modules.size)
        FileUtils.remove_entry(custom_cachedir)
      end
    end

    context 'when opts[:force_update] is true' do
      it 'always calls github_get, ignoring any existing cache' do
        populate_cache(File.join(tempdir, 'vendored_modules'))
        expect_any_instance_of(described_class).to receive(:github_get).at_least(:once).and_return([{ 'name' => 'v5.0.0' }])
        described_class.new(repo: repo_double, force_update: true)
      end
    end

    context 'when running against Puppet < 6' do
      it 'raises' do
        allow(Puppet).to receive(:version).and_return('5.5.10')
        populate_cache(File.join(tempdir, 'vendored_modules'), version: '5.5.10')
        expect { described_class.new(repo: repo_double) }.to raise_error(/only applies to puppet versions >= 6/)
      end
    end
  end

  describe '#component_cache' do
    subject(:vm) do
      populate_cache(File.join(tempdir, 'vendored_modules'))
      described_class.new(repo: repo_double)
    end

    let(:component) { core_modules.first } # augeas_core
    let(:desired_name) { "#{component}-puppet_agent-#{puppet_version}.json" }

    def touch_files(dir, names)
      FileUtils.mkdir_p(dir)
      names.each { |n| FileUtils.touch(File.join(dir, n)) }
    end

    it 'falls back to the default cachedir file when there is no manual_vendored_dir' do
      vm.instance_variable_set(:@manual_vendored_dir, File.join(tempdir, 'does-not-exist'))
      result = vm.component_cache(component)
      expect(result).to eq(File.join(vm.instance_variable_get(:@cachedir), desired_name))
    end

    it 'falls back to the default cachedir file when manual dir has zero matches' do
      manual_dir = Dir.mktmpdir
      touch_files(manual_dir, ['some_other_component-puppet_agent-1.0.0.json'])
      vm.instance_variable_set(:@manual_vendored_dir, manual_dir)
      result = vm.component_cache(component)
      expect(result).to eq(File.join(vm.instance_variable_get(:@cachedir), desired_name))
      FileUtils.remove_entry(manual_dir)
    end

    it 'uses the single manual cache file when exactly one match is found' do
      manual_dir = Dir.mktmpdir
      touch_files(manual_dir, ["#{component}-puppet_agent-9.0.0.json"])
      vm.instance_variable_set(:@manual_vendored_dir, manual_dir)
      result = vm.component_cache(component)
      expect(result).to eq(File.join(manual_dir, "#{component}-puppet_agent-9.0.0.json"))
      FileUtils.remove_entry(manual_dir)
    end

    it 'uses the exact version match when multiple manual caches exist and one matches exactly' do
      manual_dir = Dir.mktmpdir
      touch_files(manual_dir, [desired_name, "#{component}-puppet_agent-1.0.0.json"])
      vm.instance_variable_set(:@manual_vendored_dir, manual_dir)
      result = vm.component_cache(component)
      expect(result).to eq(File.join(manual_dir, desired_name))
      FileUtils.remove_entry(manual_dir)
    end

    it 'uses the latest major-version match when no exact match exists' do
      major = vm.instance_variable_get(:@puppet_major_version).to_s
      manual_dir = Dir.mktmpdir
      touch_files(manual_dir, ["#{component}-puppet_agent-#{major}.1.0.json", "#{component}-puppet_agent-1.0.0.json"])
      vm.instance_variable_set(:@manual_vendored_dir, manual_dir)
      result = vm.component_cache(component)
      expect(result).to eq(File.join(manual_dir, "#{component}-puppet_agent-#{major}.1.0.json"))
      FileUtils.remove_entry(manual_dir)
    end

    it 'falls back to the latest supplied version when neither exact nor major-version matches exist' do
      # Neither of these matches the current major version (8.x), and both
      # are numerically higher than the desired 8.13.0, so the "use latest
      # supplied" fallback should pick the highest of the two (11.0.0).
      manual_dir = Dir.mktmpdir
      touch_files(manual_dir, ["#{component}-puppet_agent-9.0.0.json", "#{component}-puppet_agent-11.0.0.json"])
      vm.instance_variable_set(:@manual_vendored_dir, manual_dir)
      result = vm.component_cache(component)
      expect(result).to eq(File.join(manual_dir, "#{component}-puppet_agent-11.0.0.json"))
      FileUtils.remove_entry(manual_dir)
    end

    it 'skips the manual dir entirely when force_update is true' do
      manual_dir = Dir.mktmpdir
      touch_files(manual_dir, ["#{component}-puppet_agent-9.0.0.json"])
      vm.instance_variable_set(:@manual_vendored_dir, manual_dir)
      vm.instance_variable_set(:@force_update, true)
      result = vm.component_cache(component)
      expect(result).to eq(File.join(vm.instance_variable_get(:@cachedir), desired_name))
      FileUtils.remove_entry(manual_dir)
    end
  end

  describe '#version_from_file' do
    subject(:vm) do
      populate_cache(File.join(tempdir, 'vendored_modules'))
      described_class.new(repo: repo_double)
    end

    it 'parses the embedded puppet_agent version out of the filename' do
      expect(vm.version_from_file('/some/path/augeas_core-puppet_agent-8.13.0.json')).to eq(Gem::Version.new('8.13.0'))
    end
  end

  describe '#puppetfile_missing_vendored' do
    subject(:vm) do
      populate_cache(File.join(tempdir, 'vendored_modules'))
      described_class.new(repo: repo_double)
    end

    it 'records core modules that are absent from the Puppetfile' do
      existing_module = double('r10k_module', name: core_modules.first)
      puppetfile = double('puppetfile')
      allow(puppetfile).to receive(:load)
      allow(puppetfile).to receive(:modules).and_return([existing_module])

      vm.puppetfile_missing_vendored(puppetfile)

      expect(vm.missing_vendored.size).to eq(core_modules.size - 1)
      missing_names = vm.missing_vendored.map { |h| h.keys.first }
      expect(missing_names).not_to include("puppetlabs-#{core_modules.first}")
      expect(missing_names).to include("puppetlabs-#{core_modules[1]}")
    end

    it 'rewrites ssh urls to https for the missing entries' do
      puppetfile = double('puppetfile')
      allow(puppetfile).to receive(:load)
      allow(puppetfile).to receive(:modules).and_return([])

      vm.puppetfile_missing_vendored(puppetfile)

      entry = vm.missing_vendored.first.values.first
      expect(entry[:git]).to start_with('https://github.com/')
      expect(entry[:git]).not_to include('git@github.com:')
    end
  end

  describe '#query_or_cache' do
    subject(:vm) do
      populate_cache(File.join(tempdir, 'vendored_modules'))
      described_class.new(repo: repo_double)
    end

    it 'reads from the cache file when it already exists' do
      cache_file = File.join(Dir.mktmpdir, 'cached.json')
      File.write(cache_file, MultiJson.dump([{ 'name' => 'v1.0.0' }]))
      expect(vm).not_to receive(:github_get)
      result = vm.query_or_cache('https://api.github.com/repos/puppetlabs/x/tags', nil, cache_file)
      expect(result).to eq([{ 'name' => 'v1.0.0' }])
    end

    it 'calls github_get and writes the cache when the file does not exist' do
      cache_file = File.join(Dir.mktmpdir, 'missing.json')
      allow(vm).to receive(:github_get).and_return([{ 'name' => 'v2.0.0' }])
      result = vm.query_or_cache('https://api.github.com/repos/puppetlabs/x/tags', nil, cache_file)
      expect(result).to eq([{ 'name' => 'v2.0.0' }])
      expect(File.exist?(cache_file)).to be true
      expect(MultiJson.load(File.read(cache_file))).to eq([{ 'name' => 'v2.0.0' }])
    end
  end

  describe '#github_get' do
    subject(:vm) do
      populate_cache(File.join(tempdir, 'vendored_modules'))
      described_class.new(repo: repo_double)
    end

    it 'returns the parsed json body on a 200 response' do
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      def response.body
        MultiJson.dump([{ 'name' => 'v3.0.0' }])
      end
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:request).and_return(response)

      result = vm.github_get('https://api.github.com/repos/puppetlabs/puppetlabs-augeas_core/tags', nil)
      expect(result).to eq([{ 'name' => 'v3.0.0' }])
    end

    it 'passes along query params when given' do
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      def response.body
        MultiJson.dump([{ 'name' => 'v4.0.0' }])
      end
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:request).and_return(response)

      result = vm.github_get('https://api.github.com/repos/puppetlabs/puppetlabs-augeas_core/tags', { 'per_page' => '1' })
      expect(result).to eq([{ 'name' => 'v4.0.0' }])
    end

    it 'raises with the ratelimit headers on a non-200 response' do
      response = Net::HTTPForbidden.new('1.1', '403', 'Forbidden')
      def response.to_hash
        { 'x-ratelimit-remaining' => ['0'] }
      end
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:request).and_return(response)

      expect { vm.github_get('https://api.github.com/repos/puppetlabs/puppetlabs-augeas_core/tags', nil) }
        .to raise_error(/403 Forbidden/)
    end
  end

  describe '#read_json_dump and #write_json_dump' do
    subject(:vm) do
      populate_cache(File.join(tempdir, 'vendored_modules'))
      described_class.new(repo: repo_double)
    end

    it 'round-trips json data through a file' do
      file = File.join(Dir.mktmpdir, 'roundtrip.json')
      vm.write_json_dump(file, [{ 'name' => 'v1.0.0' }])
      expect(vm.read_json_dump(file)).to eq([{ 'name' => 'v1.0.0' }])
    end
  end
end
