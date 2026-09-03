require 'spec_helper'
require 'puppetlabs-onceover/cli/run'

describe PuppetlabsOnceover::CLI::Run do
  describe '.command' do
    it 'builds a memoized Cri::Command named run' do
      cmd = described_class.command
      expect(cmd).to be_a(Cri::Command)
      expect(cmd.name).to eq('run')
      expect(described_class.command).to equal(cmd)
    end

    it 'prints help and exits 0 when run directly' do
      allow_any_instance_of(Object).to receive(:exit)
      expect { described_class.command.run([]) }.to output(/Runs either the spec or acceptance tests/).to_stdout
    end

    it 'registers the spec and acceptance subcommands' do
      names = described_class.command.subcommands.map(&:name)
      expect(names).to include('spec', 'acceptance')
    end
  end

  describe PuppetlabsOnceover::CLI::Run::Spec do
    describe '.command' do
      it 'builds a memoized Cri::Command named spec' do
        cmd = described_class.command
        expect(cmd).to be_a(Cri::Command)
        expect(cmd.name).to eq('spec')
        expect(described_class.command).to equal(cmd)
      end

      it 'deploys locally then prepares and runs the spec suite' do
        repo = double('repo', onceover_yaml: '/some/repo/.onceover.yaml')
        config = double('config')
        deploy = double('deploy', deploy_local: nil)
        runner = double('runner', prepare!: nil, run_spec!: nil)

        allow(PuppetlabsOnceover::Controlrepo).to receive(:new).and_return(repo)
        allow(PuppetlabsOnceover::TestConfig).to receive(:new).and_return(config)
        allow(PuppetlabsOnceover::Deploy).to receive(:new).and_return(deploy)
        allow(PuppetlabsOnceover::Runner).to receive(:new).and_return(runner)

        described_class.command.run([])

        expect(deploy).to have_received(:deploy_local).with(repo, anything)
        expect(PuppetlabsOnceover::Runner).to have_received(:new).with(repo, config, :spec)
        expect(runner).to have_received(:prepare!)
        expect(runner).to have_received(:run_spec!)
      end
    end
  end

  describe PuppetlabsOnceover::CLI::Run::Acceptance do
    describe '.command' do
      it 'builds a memoized Cri::Command named acceptance' do
        cmd = described_class.command
        expect(cmd).to be_a(Cri::Command)
        expect(cmd.name).to eq('acceptance')
        expect(described_class.command).to equal(cmd)
      end

      it 'warns about deprecation then prepares and runs the acceptance suite' do
        repo = double('repo', onceover_yaml: '/some/repo/.onceover.yaml')
        config = double('config')
        runner = double('runner', prepare!: nil, run_acceptance!: nil)

        allow(PuppetlabsOnceover::Controlrepo).to receive(:new).and_return(repo)
        allow(PuppetlabsOnceover::TestConfig).to receive(:new).and_return(config)
        allow(PuppetlabsOnceover::Runner).to receive(:new).and_return(runner)

        expect { described_class.command.run([]) }.to output(/DEPRECATION/).to_stderr

        expect(PuppetlabsOnceover::Runner).to have_received(:new).with(repo, config, :acceptance)
        expect(runner).to have_received(:prepare!)
        expect(runner).to have_received(:run_acceptance!)
      end
    end
  end
end
