require 'spec_helper'
require 'puppetlabs-onceover/cli/show'

describe PuppetlabsOnceover::CLI::Show do
  describe '.command' do
    it 'builds a memoized Cri::Command named show' do
      cmd = described_class.command
      expect(cmd).to be_a(Cri::Command)
      expect(cmd.name).to eq('show')
      expect(described_class.command).to equal(cmd)
    end

    it 'prints help and exits 0 when run directly' do
      allow_any_instance_of(Object).to receive(:exit)
      expect { described_class.command.run([]) }.to output(/Shows the current state of things/).to_stdout
    end

    it 'registers the repo and puppetfile subcommands' do
      names = described_class.command.subcommands.map(&:name)
      expect(names).to include('repo', 'puppetfile')
    end
  end

  describe PuppetlabsOnceover::CLI::Show::Repo do
    describe '.command' do
      it 'builds a memoized Cri::Command named repo' do
        cmd = described_class.command
        expect(cmd).to be_a(Cri::Command)
        expect(cmd.name).to eq('repo')
        expect(described_class.command).to equal(cmd)
      end

      it 'prints repo and test config information and exits 0' do
        allow_any_instance_of(Object).to receive(:exit)
        repo = double('repo', to_s: 'REPO INFO', onceover_yaml: '/some/repo/.onceover.yaml')
        config = double('config', to_s: 'CONFIG INFO')
        allow(PuppetlabsOnceover::Controlrepo).to receive(:new).and_return(repo)
        allow(PuppetlabsOnceover::TestConfig).to receive(:new).and_return(config)

        expect { described_class.command.run([]) }.to output(/REPO INFO/).to_stdout
        expect { described_class.command.run([]) }.to output(/CONFIG INFO/).to_stdout
        expect(PuppetlabsOnceover::TestConfig).to have_received(:new).with(repo.onceover_yaml, anything).at_least(:once)
      end
    end
  end

  describe PuppetlabsOnceover::CLI::Show::Puppetfile do
    describe '.command' do
      it 'builds a memoized Cri::Command named puppetfile' do
        cmd = described_class.command
        expect(cmd).to be_a(Cri::Command)
        expect(cmd.name).to eq('puppetfile')
        expect(described_class.command).to equal(cmd)
      end

      it 'prints the puppetfile table and exits 0' do
        allow_any_instance_of(Object).to receive(:exit)
        repo = double('repo', print_puppetfile_table: nil)
        allow(PuppetlabsOnceover::Controlrepo).to receive(:new).and_return(repo)

        described_class.command.run([])

        expect(repo).to have_received(:print_puppetfile_table)
      end
    end
  end
end
