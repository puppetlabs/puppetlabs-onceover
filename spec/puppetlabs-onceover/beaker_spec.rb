require 'spec_helper'
require 'puppetlabs-onceover/beaker'

# The `beaker`/`beaker-rspec` gems are intentionally NOT in this project's Gemfile
# (removing that dependency is the whole point of this fork -- see CAT-2770 et al).
# beaker.rb's deprecated, still-shippped `deploy_controlrepo_on`/`provision_and_test`/
# `host_create` methods `require 'beaker-rspec'` / `require 'beaker/network_manager'`
# and reference `::Beaker::NetworkManager` inline. To cover those code paths without
# pulling the real (large, unmaintained-for-this-repo's-purposes) beaker gems back in,
# stand in a minimal fake `::Beaker::NetworkManager` and make the specific `require`
# calls those methods make into no-ops.
module ::Beaker
  unless defined?(::Beaker::NetworkManager)
    class NetworkManager
    end
  end
end

describe "PuppetlabsOnceover::Beaker" do
  before(:each) do
    allow(Kernel).to receive(:warn)
    allow_any_instance_of(Object).to receive(:require).and_wrap_original do |original, name|
      %w[beaker-rspec beaker/network_manager].include?(name) || original.call(name)
    end
  end

  describe ".facts_to_vagrant_box" do
    it "maps Ubuntu facts to a puppetlabs vagrant box name" do
      facts = { 'os' => { 'distro' => { 'id' => 'Ubuntu', 'release' => { 'major' => '20.04' } }, 'architecture' => 'x86_64' } }
      expect(PuppetlabsOnceover::Beaker.facts_to_vagrant_box(facts)).to eq('puppetlabs/ubuntu-20.04-64-puppet')
    end

    it "maps Debian facts to a puppetlabs vagrant box name" do
      facts = { 'os' => { 'distro' => { 'id' => 'Debian', 'release' => { 'full' => '10.9' } }, 'architecture' => 'x86_64' } }
      expect(PuppetlabsOnceover::Beaker.facts_to_vagrant_box(facts)).to eq('puppetlabs/Debian-10.9-64-puppet')
    end

    it "maps RedHat family facts to a centos vagrant box name" do
      facts = { 'os' => { 'family' => 'RedHat', 'release' => { 'major' => '7', 'minor' => '9' }, 'architecture' => 'x86_64' } }
      expect(PuppetlabsOnceover::Beaker.facts_to_vagrant_box(facts)).to eq('puppetlabs/centos-7.9-64-puppet')
    end

    it "returns UNKNOWN when the OS cannot be determined" do
      facts = { 'os' => { 'family' => 'SomeWeirdOS', 'architecture' => 'x86_64' } }
      expect(PuppetlabsOnceover::Beaker.facts_to_vagrant_box(facts)).to eq('UNKNOWN')
    end

    it "detects 32-bit architectures" do
      facts = { 'os' => { 'family' => 'RedHat', 'release' => { 'major' => '6', 'minor' => '0' } }, 'architecture' => 'i386' }
      expect(PuppetlabsOnceover::Beaker.facts_to_vagrant_box(facts)).to eq('puppetlabs/centos-6.0-32-puppet')
    end

    it "recurses over an array of factsets" do
      facts = [
        { 'os' => { 'family' => 'RedHat', 'release' => { 'major' => '7', 'minor' => '0' }, 'architecture' => 'x86_64' } },
        { 'os' => { 'family' => 'SomeWeirdOS', 'architecture' => 'x86_64' } }
      ]
      result = PuppetlabsOnceover::Beaker.facts_to_vagrant_box(facts)
      expect(result).to eq(['puppetlabs/centos-7.0-64-puppet', 'UNKNOWN'])
    end

    it "does not blow up when the facts hash does not have the expected 'os' shape" do
      expect(PuppetlabsOnceover::Beaker.facts_to_vagrant_box({ 'architecture' => 'x86_64' })).to eq('UNKNOWN')
    end
  end

  describe ".facts_to_platform" do
    it "maps RedHat family facts to an 'el' platform string" do
      facts = { 'os' => { 'family' => 'RedHat', 'release' => { 'major' => '7' }, 'architecture' => 'x86_64' } }
      expect(PuppetlabsOnceover::Beaker.facts_to_platform(facts)).to eq('el-7-64')
    end

    it "maps Ubuntu facts to an 'ubuntu' platform string" do
      facts = { 'os' => { 'family' => 'Debian', 'distro' => { 'id' => 'Ubuntu', 'release' => { 'major' => '20.04' } }, 'architecture' => 'x86_64' } }
      expect(PuppetlabsOnceover::Beaker.facts_to_platform(facts)).to eq('ubuntu-20.04-64')
    end

    it "maps Debian facts to a 'debian' platform string" do
      facts = { 'os' => { 'family' => 'Debian', 'distro' => { 'id' => 'Debian', 'release' => { 'full' => '10.9' } }, 'architecture' => 'x86_64' } }
      expect(PuppetlabsOnceover::Beaker.facts_to_platform(facts)).to eq('debian-10.9-64')
    end

    it "detects 32-bit architectures" do
      facts = { 'os' => { 'family' => 'RedHat', 'release' => { 'major' => '6' }, 'architecture' => 'i386' } }
      expect(PuppetlabsOnceover::Beaker.facts_to_platform(facts)).to eq('el-6-32')
    end

    it "produces a nil-nil platform string when nothing matches" do
      facts = { 'os' => { 'family' => 'SomeWeirdOS', 'architecture' => 'x86_64' } }
      expect(PuppetlabsOnceover::Beaker.facts_to_platform(facts)).to eq('--64')
    end

    it "recurses over an array of factsets" do
      facts = [
        { 'os' => { 'family' => 'RedHat', 'release' => { 'major' => '7' }, 'architecture' => 'x86_64' } },
        { 'os' => { 'family' => 'RedHat', 'release' => { 'major' => '8' }, 'architecture' => 'x86_64' } }
      ]
      expect(PuppetlabsOnceover::Beaker.facts_to_platform(facts)).to eq(['el-7-64', 'el-8-64'])
    end
  end

  describe ".deploy_controlrepo_on" do
    it "installs r10k, git, copies the r10k config, and deploys via r10k on a single host" do
      host = double('host')
      repo = double('repo', r10k_config_file: '/tmp/r10k.yaml')

      allow(PuppetlabsOnceover::Beaker).to receive(:require).and_return(true)
      allow(host).to receive(:is_a?).with(Array).and_return(false)
      allow(PuppetlabsOnceover::Beaker).to receive(:install_r10k_on)
      allow(host).to receive(:install_package).with('git')
      allow(PuppetlabsOnceover::Beaker).to receive(:scp_to)
      allow(PuppetlabsOnceover::Beaker).to receive(:r10k_deploy)

      PuppetlabsOnceover::Beaker.deploy_controlrepo_on(host, repo)

      expect(PuppetlabsOnceover::Beaker).to have_received(:install_r10k_on).with(host)
      expect(host).to have_received(:install_package).with('git')
      expect(PuppetlabsOnceover::Beaker).to have_received(:scp_to).with(host, '/tmp/r10k.yaml', '/tmp/r10k.yaml')
      expect(PuppetlabsOnceover::Beaker).to have_received(:r10k_deploy).with(host, { puppetfile: true, configfile: '/tmp/r10k.yaml' })
    end

    it "recurses when given an array of hosts (accepted quirk: iterates `hosts`, an undefined local, not the `host` array param)" do
      host_array = double('host_array')
      allow(host_array).to receive(:is_a?).with(Array).and_return(true)
      repo = double('repo', r10k_config_file: '/tmp/r10k.yaml')

      allow(PuppetlabsOnceover::Beaker).to receive(:install_r10k_on)
      allow(host_array).to receive(:install_package)
      allow(PuppetlabsOnceover::Beaker).to receive(:scp_to)
      allow(PuppetlabsOnceover::Beaker).to receive(:r10k_deploy)

      # `hosts.each { ... }` inside the `if host.is_a?(Array)` branch references an
      # undefined local `hosts` (not the `host` param) -- a real bug in the source.
      # It raises NameError immediately, so the array-recursion branch never actually
      # recurses; we assert the crash rather than pretending it works.
      expect { PuppetlabsOnceover::Beaker.deploy_controlrepo_on(host_array, repo) }.to raise_error(NameError, /hosts/)
    end
  end

  describe ".provision_and_test" do
    # provision_and_test's 4th positional param defaults to `PuppetlabsOnceover::Controlrepo.new`
    # -- Ruby evaluates that default for any omitted arg before the method body (and its own
    # raise checks) ever runs, and a real `Controlrepo.new` throws outside an actual controlrepo.
    # Always pass an explicit (unused) repo double as the 4th arg to avoid tripping that default.
    let(:unused_repo) { double('repo') }

    it "raises when given an array of hosts" do
      expect do
        PuppetlabsOnceover::Beaker.provision_and_test([double('host')], 'role::example', {}, unused_repo)
      end.to raise_error(RuntimeError, /must be a single host object/)
    end

    it "raises when puppet_class is not a String" do
      expect do
        PuppetlabsOnceover::Beaker.provision_and_test(double('host'), :not_a_string, {}, unused_repo)
      end.to raise_error(RuntimeError, /must be a single Class/)
    end

    it "provisions (when host is not up), applies the manifest, checks idempotency, and cleans up" do
      host = double('host', up?: false)
      network_manager = double('network_manager')
      allow(network_manager).to receive(:instance_variable_set)
      allow(network_manager).to receive(:provision)
      allow(network_manager).to receive(:proxy_package_manager)
      allow(network_manager).to receive(:validate)
      allow(network_manager).to receive(:configure)
      allow(network_manager).to receive(:cleanup)
      allow(Beaker::NetworkManager).to receive(:new).and_return(network_manager)

      apply_calls = []
      allow(PuppetlabsOnceover::Beaker).to receive(:apply_manifest_on) do |h, manifest, opts|
        apply_calls << [h, manifest, opts]
      end
      allow(PuppetlabsOnceover::Beaker).to receive(:options).and_return({})
      allow(PuppetlabsOnceover::Beaker).to receive(:logger).and_return(double('logger'))

      PuppetlabsOnceover::Beaker.provision_and_test(host, 'role::example', {}, unused_repo)

      expect(network_manager).to have_received(:provision)
      expect(network_manager).to have_received(:cleanup)
      expect(apply_calls.map { |c| c[2] }).to include({ catch_failures: true }, { catch_changes: true })
    end

    it "skips provisioning when the host is already up, and skips idempotency check when disabled" do
      host = double('host', up?: true)
      network_manager = double('network_manager')
      allow(network_manager).to receive(:instance_variable_set)
      allow(network_manager).to receive(:cleanup)
      allow(Beaker::NetworkManager).to receive(:new).and_return(network_manager)

      apply_calls = []
      allow(PuppetlabsOnceover::Beaker).to receive(:apply_manifest_on) do |h, manifest, opts|
        apply_calls << [h, manifest, opts]
      end
      allow(PuppetlabsOnceover::Beaker).to receive(:options).and_return({})
      allow(PuppetlabsOnceover::Beaker).to receive(:logger).and_return(double('logger'))

      PuppetlabsOnceover::Beaker.provision_and_test(host, 'role::example', { check_idempotency: false, runs_before_idempotency: 2 }, unused_repo)

      expect(apply_calls.size).to eq(2)
      expect(apply_calls.map { |c| c[2] }).to eq([{ catch_failures: true }, { catch_failures: true }])
    end
  end

  describe ".match_indentation" do
    it "sets the logger's line_prefix based on the scoped_id depth" do
      test = double('test', metadata: { scoped_id: '1:2:3' })
      logger = double('logger')
      expect(logger).to receive(:line_prefix=).with('    ')
      PuppetlabsOnceover::Beaker.match_indentation(test, logger)
    end

    it "uses no prefix for a top-level scoped_id" do
      test = double('test', metadata: { scoped_id: '1' })
      logger = double('logger')
      expect(logger).to receive(:line_prefix=).with('')
      PuppetlabsOnceover::Beaker.match_indentation(test, logger)
    end
  end

  describe ".host_create" do
    it "builds a single host via a NetworkManager, wires up a down! method, and returns it" do
      nodes = { HOSTS: { 'centos7' => { platform: 'el-7-x86_64' }, 'other' => { platform: 'ubuntu' } }, other_opt: 'value' }

      host_double = double('host')
      allow(host_double).to receive(:instance_variable_set)
      allow(host_double).to receive(:define_singleton_method)

      network_manager = double('network_manager')
      allow(network_manager).to receive(:provision)
      allow(network_manager).to receive(:proxy_package_manager)
      allow(network_manager).to receive(:validate)
      allow(network_manager).to receive(:configure)
      allow(network_manager).to receive(:instance_variable_get).with(:@hosts).and_return([host_double])
      allow(Beaker::NetworkManager).to receive(:new).and_return(network_manager)
      allow(PuppetlabsOnceover::Beaker).to receive(:logger).and_return(double('logger'))
      allow(PuppetlabsOnceover::Beaker).to receive(:hosts).and_return([host_double])

      result = PuppetlabsOnceover::Beaker.host_create('centos7', nodes)

      expect(result).to eq(host_double)
      expect(Beaker::NetworkManager).to have_received(:new) do |opts, _logger|
        expect(opts[:HOSTS]).to eq({ 'centos7' => { platform: 'el-7-x86_64' } })
        expect(opts[:other_opt]).to eq('value')
      end
    end

    it "supports the default_proc string/symbol key fallback on current_opts" do
      nodes = { HOSTS: { 'centos7' => {} } }
      captured_opts = nil

      host_double = double('host')
      allow(host_double).to receive(:instance_variable_set)
      allow(host_double).to receive(:define_singleton_method)

      network_manager = double('network_manager')
      allow(network_manager).to receive(:provision)
      allow(network_manager).to receive(:proxy_package_manager)
      allow(network_manager).to receive(:validate)
      allow(network_manager).to receive(:configure)
      allow(network_manager).to receive(:instance_variable_get).with(:@hosts).and_return([host_double])
      allow(Beaker::NetworkManager).to receive(:new) do |opts, _logger|
        captured_opts = opts
        network_manager
      end
      allow(PuppetlabsOnceover::Beaker).to receive(:logger).and_return(double('logger'))
      allow(PuppetlabsOnceover::Beaker).to receive(:hosts).and_return([host_double])

      PuppetlabsOnceover::Beaker.host_create('centos7', nodes)

      expect(captured_opts[:HOSTS]).to eq({ 'centos7' => {} })
      expect(captured_opts['HOSTS']).to eq({ 'centos7' => {} })
    end

    it "raises if the network manager created more than one host" do
      nodes = { HOSTS: { 'centos7' => {} } }

      network_manager = double('network_manager')
      allow(network_manager).to receive(:provision)
      allow(network_manager).to receive(:proxy_package_manager)
      allow(network_manager).to receive(:validate)
      allow(network_manager).to receive(:configure)
      allow(network_manager).to receive(:instance_variable_get).with(:@hosts).and_return([double('a'), double('b')])
      allow(Beaker::NetworkManager).to receive(:new).and_return(network_manager)
      allow(PuppetlabsOnceover::Beaker).to receive(:logger).and_return(double('logger'))
      allow(PuppetlabsOnceover::Beaker).to receive(:hosts).and_return([double('a'), double('b')])

      expect do
        PuppetlabsOnceover::Beaker.host_create('centos7', nodes)
      end.to raise_error(RuntimeError, /too many machines/)
    end
  end
end
