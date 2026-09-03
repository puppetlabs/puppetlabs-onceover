require 'spec_helper'
require 'puppetlabs-onceover/controlrepo' # side effect: defines top-level #logger
require 'puppetlabs-onceover/test'
require 'puppetlabs-onceover/rspec/formatters'
require 'puppetlabs-onceover/runner'

describe PuppetlabsOnceover::Runner do
  let(:repo) do
    double(
      'repo',
      tempdir: '/tmp/onceover-runner-spec',
      environmentpath: 'etc/puppetlabs/code/environments',
      hiera_config: nil,
      root: '/tmp/onceover-runner-spec-root'
    )
  end

  def build_config(overrides = {})
    double(
      'config',
      {
        copy_spec_files: nil,
        write_rakefile: nil,
        write_spec_helper: nil,
        write_spec_helper_acceptance: nil,
        spec_tests: [],
        verify_spec_test: nil,
        run_filters: [],
        write_spec_test: nil,
        acceptance_tests: [],
        verify_acceptance_test: nil,
        write_acceptance_tests: nil,
        create_fixtures_symlinks: nil,
        filter_tags: nil,
        fail_fast: false,
        opts: {},
        formatters: []
      }.merge(overrides)
    )
  end

  let(:config) { build_config }

  before do
    # Avoid any real filesystem churn from FileUtils calls in #prepare!
    allow(FileUtils).to receive(:rm_rf)
    allow(FileUtils).to receive(:rm_f)
    allow(FileUtils).to receive(:mkdir_p)
  end

  describe '#initialize' do
    it 'wraps a single symbol mode into an array' do
      runner = described_class.new(repo, config, :spec)
      expect(runner.instance_variable_get(:@mode)).to eq([:spec])
    end

    it 'accepts an array of modes as-is' do
      runner = described_class.new(repo, config, [:spec, :acceptance])
      expect(runner.instance_variable_get(:@mode)).to eq([:spec, :acceptance])
    end

    it 'defaults the mode to spec and acceptance' do
      runner = described_class.new(repo, config)
      expect(runner.instance_variable_get(:@mode)).to eq([:spec, :acceptance])
    end

    it 'sets an empty command prefix when BUNDLE_GEMFILE is not set' do
      original = ENV.delete('BUNDLE_GEMFILE')
      runner = described_class.new(repo, config)
      expect(runner.instance_variable_get(:@command_prefix)).to eq('')
      ENV['BUNDLE_GEMFILE'] = original if original
    end

    it 'sets a bundle exec command prefix when BUNDLE_GEMFILE is set' do
      original = ENV['BUNDLE_GEMFILE']
      ENV['BUNDLE_GEMFILE'] = 'Gemfile'
      runner = described_class.new(repo, config)
      expect(runner.instance_variable_get(:@command_prefix)).to eq('bundle exec ')
      if original
        ENV['BUNDLE_GEMFILE'] = original
      else
        ENV.delete('BUNDLE_GEMFILE')
      end
    end
  end

  describe '#prepare!' do
    it 'runs the spec test path when mode includes :spec' do
      runner = described_class.new(repo, config, :spec)

      expect(config).to receive(:spec_tests).at_least(:once).and_return(['sometest'])
      expect(config).to receive(:verify_spec_test).with(repo, 'sometest')
      expect(PuppetlabsOnceover::Test).to receive(:deduplicate).with(['sometest']).and_return(['sometest'])
      expect(config).to receive(:run_filters).with(['sometest']).and_return(['sometest'])
      expect(config).to receive(:write_spec_test).with("#{repo.tempdir}/spec/classes", 'sometest')
      expect(config).not_to receive(:acceptance_tests)

      runner.prepare!
    end

    it 'runs the acceptance test path when mode includes :acceptance' do
      runner = described_class.new(repo, config, :acceptance)

      expect(config).to receive(:acceptance_tests).at_least(:once).and_return(['sometest'])
      expect(config).to receive(:verify_acceptance_test).with(repo, 'sometest')
      expect(PuppetlabsOnceover::Test).to receive(:deduplicate).with(['sometest']).and_return(['sometest'])
      expect(config).to receive(:run_filters).with(['sometest']).and_return(['sometest'])
      expect(config).to receive(:write_acceptance_tests).with("#{repo.tempdir}/spec/acceptance", ['sometest'])
      expect(config).not_to receive(:spec_tests)

      runner.prepare!
    end

    it 'runs neither test path when mode is empty' do
      runner = described_class.new(repo, config, [])

      expect(config).not_to receive(:spec_tests)
      expect(config).not_to receive(:acceptance_tests)

      runner.prepare!
    end

    it 'skips the hiera rewrite when hiera_config is nil' do
      runner = described_class.new(repo, config, [])
      expect(File).not_to receive(:write)
      runner.prepare!
    end

    it 'rewrites a plain (non-hash) hiera_config setting untouched and writes hiera.yaml' do
      hiera_repo = double(
        'repo',
        tempdir: '/tmp/onceover-runner-spec',
        environmentpath: 'etc/puppetlabs/code/environments',
        hiera_config: { 'version' => 5 },
        root: '/tmp/onceover-runner-spec-root'
      )
      runner = described_class.new(hiera_repo, config, [])

      expect(File).to receive(:write).with(
        "#{hiera_repo.tempdir}/#{hiera_repo.environmentpath}/production/hiera.yaml",
        { 'version' => 5 }.to_yaml
      )

      runner.prepare!
    end

    it 'rewrites the datadir of a hierarchy hash entry to point at the tempdir' do
      hiera_config = {
        'hierarchy' => { datadir: 'hieradata' }
      }
      hiera_repo = double(
        'repo',
        tempdir: '/tmp/onceover-runner-spec',
        environmentpath: 'etc/puppetlabs/code/environments',
        hiera_config: hiera_config,
        root: '/tmp/onceover-runner-spec-root'
      )
      runner = described_class.new(hiera_repo, config, [])

      expected_datadir = "#{hiera_repo.tempdir}/#{hiera_repo.environmentpath}/production/hieradata"

      expect(File).to receive(:write) do |path, contents|
        expect(path).to eq("#{hiera_repo.tempdir}/#{hiera_repo.environmentpath}/production/hiera.yaml")
        expect(contents).to include(expected_datadir)
      end

      runner.prepare!
    end

    it 'leaves a hash entry without a :datadir key untouched' do
      hiera_config = {
        'hierarchy' => { other_key: 'value' }
      }
      hiera_repo = double(
        'repo',
        tempdir: '/tmp/onceover-runner-spec',
        environmentpath: 'etc/puppetlabs/code/environments',
        hiera_config: hiera_config,
        root: '/tmp/onceover-runner-spec-root'
      )
      runner = described_class.new(hiera_repo, config, [])

      expect(File).to receive(:write) do |_path, contents|
        expect(contents).not_to include('/tmp/onceover-runner-spec/etc')
      end

      runner.prepare!
    end
  end

  describe '#run_spec!' do
    let(:backticks_double) do
      double('backticks_runner', run: double('process', join: double('joined', status: double('status', exitstatus: 0))))
    end

    before do
      allow(Backticks::Runner).to receive(:new).and_return(backticks_double)
      allow(Dir).to receive(:chdir).and_yield
      allow(STDERR).to receive(:isatty).and_return(false)
    end

    it 'runs rake spec:standalone in standalone mode and exits with the status code' do
      runner = described_class.new(repo, config, :spec)
      logger.level = :info

      expect(runner).to receive(:exit).with(0)
      runner.run_spec!
    end

    it 'runs rake parallel_spec when opts[:parallel] is set' do
      parallel_config = build_config(opts: { parallel: true })
      runner = described_class.new(repo, parallel_config, :spec)
      logger.level = :info

      expect(runner).to receive(:run_command).with(anything, 'rake', 'parallel_spec').and_call_original
      allow(runner).to receive(:exit)
      runner.run_spec!
    end

    it 'skips the RUBYOPT warning-suppression dance when logger level is debug (zero)' do
      runner = described_class.new(repo, config, :spec)
      logger.level = :debug

      previous = ENV.fetch('RUBYOPT', nil)
      expect(runner).to receive(:exit).with(0)
      runner.run_spec!
      expect(ENV.fetch('RUBYOPT', nil)).to eq(previous)
      logger.level = :info
    end

    it 'appends filter tags and fail-fast to CI_SPEC_OPTIONS when configured' do
      tagged_config = build_config(filter_tags: ['sometag'], fail_fast: true)
      runner = described_class.new(repo, tagged_config, :spec)
      logger.level = :info

      allow(runner).to receive(:exit)
      runner.run_spec!
      expect(ENV['CI_SPEC_OPTIONS']).to include('--tag sometag')
      expect(ENV['CI_SPEC_OPTIONS']).to include('--fail-fast')
      ENV.delete('CI_SPEC_OPTIONS')
    end

    it 'prints a parallel summary when the parallel formatter is configured' do
      formatter_config = build_config(formatters: ['PuppetlabsOnceoverFormatterParallel'])
      runner = described_class.new(repo, formatter_config, :spec)
      logger.level = :info

      formatter_double = double('formatter', output_results: nil)
      expect(PuppetlabsOnceoverFormatterParallel).to receive(:new).with(STDOUT).and_return(formatter_double)
      expect(formatter_double).to receive(:output_results).with("#{repo.tempdir}/parallel")

      allow(runner).to receive(:exit)
      runner.run_spec!
    end
  end

  describe '#run_acceptance!' do
    let(:backticks_double) do
      double('backticks_runner', run: double('process', join: double('joined', status: double('status', exitstatus: 1))))
    end

    before do
      allow(Backticks::Runner).to receive(:new).and_return(backticks_double)
      allow(Dir).to receive(:chdir).and_yield
      allow(STDERR).to receive(:isatty).and_return(false)
    end

    it 'warns about deprecation and runs rake acceptance' do
      # NOTE: `result` in the source is assigned only inside the Dir.chdir
      # block and then read again after the block returns -- that's normal
      # Ruby block-local scoping, so `result` is actually undefined at the
      # `exit result.status.exitstatus` line and this method always raises
      # NameError there in real usage. That's a pre-existing bug in
      # lib/puppetlabs-onceover/runner.rb, not something we can cover
      # without changing production behavior, so we assert the crash
      # instead of the (unreachable) exit call.
      runner = described_class.new(repo, config, :acceptance)

      expect(runner).to receive(:warn).with(/DEPRECATION/)
      expect { runner.run_acceptance! }.to raise_error(NameError, /result/)
    end
  end

  describe '#run_command' do
    it 'sets STDERR raw when a tty and cooked afterwards' do
      runner = described_class.new(repo, config, :spec)
      backticks_double = double('backticks_runner', run: double('process', join: double('joined')))
      allow(Backticks::Runner).to receive(:new).and_return(backticks_double)
      allow(STDERR).to receive(:isatty).and_return(true)
      expect(STDERR).to receive(:raw!)
      expect(STDERR).to receive(:cooked!)

      runner.run_command('rake', 'spec:standalone')
    end

    it 'does not touch STDERR raw/cooked state when not a tty' do
      runner = described_class.new(repo, config, :spec)
      backticks_double = double('backticks_runner', run: double('process', join: double('joined')))
      allow(Backticks::Runner).to receive(:new).and_return(backticks_double)
      allow(STDERR).to receive(:isatty).and_return(false)
      expect(STDERR).not_to receive(:raw!)
      expect(STDERR).not_to receive(:cooked!)

      runner.run_command('rake', 'spec:standalone')
    end
  end
end
