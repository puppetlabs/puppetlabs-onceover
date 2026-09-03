require 'spec_helper'
require 'puppetlabs-onceover/cli'
require 'puppetlabs-onceover/cli/init'
require 'puppetlabs-onceover/cli/update'
require 'puppetlabs-onceover/cli/plugins'

describe PuppetlabsOnceover::CLI do
  describe '.command' do
    it 'builds a memoized Cri::Command named onceover' do
      cmd = described_class.command
      expect(cmd).to be_a(Cri::Command)
      expect(cmd.name).to eq('onceover')
      expect(described_class.command).to equal(cmd)
    end

    it 'prints help and exits 0 when run with no subcommand' do
      allow_any_instance_of(Object).to receive(:exit)
      expect { described_class.command.run([]) }.to output(/Tool for testing Puppet controlrepos/).to_stdout
    end

    it 'prints help and exits 0 when given -h' do
      allow_any_instance_of(Object).to receive(:exit)
      expect { described_class.command.run(['-h']) }.to output(/onceover/).to_stdout
    end

    it 'registers the show, run, init, and update subcommands' do
      names = described_class.command.subcommands.map(&:name)
      expect(names).to include('show', 'run', 'init', 'update')
    end
  end
end

describe PuppetlabsOnceover::CLI::Init do
  describe '.command' do
    it 'builds a memoized Cri::Command named init' do
      cmd = described_class.command
      expect(cmd).to be_a(Cri::Command)
      expect(cmd.name).to eq('init')
      expect(described_class.command).to equal(cmd)
    end

    it 'calls Controlrepo.init with a freshly built Controlrepo' do
      repo = double('repo')
      allow(PuppetlabsOnceover::Controlrepo).to receive(:new).and_return(repo)
      allow(PuppetlabsOnceover::Controlrepo).to receive(:init)

      described_class.command.run([])

      expect(PuppetlabsOnceover::Controlrepo).to have_received(:init).with(repo)
    end
  end
end

describe PuppetlabsOnceover::CLI::Update do
  describe '.command' do
    it 'prints help and exits 0 when run directly' do
      allow_any_instance_of(Object).to receive(:exit)
      expect { described_class.command.run([]) }.to output(/Updates stuff/).to_stdout
    end
  end

  describe PuppetlabsOnceover::CLI::Update::Puppetfile do
    it 'calls update_puppetfile on a freshly built Controlrepo and exits 0' do
      allow_any_instance_of(Object).to receive(:exit)
      repo = double('repo', update_puppetfile: nil)
      allow(PuppetlabsOnceover::Controlrepo).to receive(:new).and_return(repo)

      described_class.command.run([])

      expect(repo).to have_received(:update_puppetfile)
    end
  end
end

describe 'cli/plugins.rb' do
  it 'requires the plugins file without error, discovering zero or more onceover-* gems' do
    expect { load File.expand_path('../../lib/puppetlabs-onceover/cli/plugins.rb', __dir__) }.not_to raise_error
  end
end
