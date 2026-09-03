require 'spec_helper'
require 'puppetlabs-onceover/controlrepo'
require 'puppetlabs-onceover/vendored_modules'
require 'puppetlabs-onceover/deploy'
require 'tmpdir'
require 'fileutils'

describe PuppetlabsOnceover::Deploy do
  subject(:deploy) { described_class.new }

  # Every test gets its own scratch tempdir standing in for
  # repo.tempdir/.onceover, cleaned up afterwards so nothing leaks into the
  # real repo tree.
  let(:tempdir) { Dir.mktmpdir('deploy-spec-tempdir') }

  after do
    FileUtils.rm_rf(tempdir)
  end

  def build_repo(fixture, tempdir_override: tempdir)
    repo = PuppetlabsOnceover::Controlrepo.new(path: "spec/fixtures/controlrepos/#{fixture}")
    repo.tempdir = tempdir_override
    repo
  end

  describe '#deploy_local' do
    context 'when the controlrepo has no Puppetfile' do
      it 'defaults to skipping r10k entirely and still copies the tree' do
        repo = build_repo('minimal')

        expect(deploy).not_to receive(:system)

        result = deploy.deploy_local(repo, {})

        expect(result).to eq(tempdir)
        production_dir = "#{tempdir}/#{repo.environmentpath}/production"
        expect(File.exist?("#{production_dir}/environment.conf")).to be true
        expect(File.exist?("#{production_dir}/.onceover_manifest.json")).to be true
      end
    end

    context 'when skip_r10k is explicitly requested' do
      it 'copies the tree (including the untouched Puppetfile) but never shells out' do
        repo = build_repo('basic')

        expect(deploy).not_to receive(:system)

        deploy.deploy_local(repo, { skip_r10k: true })

        production_dir = "#{tempdir}/#{repo.environmentpath}/production"
        original_puppetfile = File.read('spec/fixtures/controlrepos/basic/Puppetfile')
        expect(File.read("#{production_dir}/Puppetfile")).to eq(original_puppetfile)
      end
    end

    context 'symlinks, directories, and plain files in the controlrepo' do
      it 'recreates symlinks, directories, and files in the copied tree' do
        repo = build_repo('deploy_test')

        deploy.deploy_local(repo, { skip_r10k: true })

        production_dir = "#{tempdir}/#{repo.environmentpath}/production"
        expect(File.symlink?("#{production_dir}/a_symlink")).to be true
        expect(File.directory?("#{production_dir}/a_dir")).to be true
        expect(File.read("#{production_dir}/a_dir/nested_file.txt")).to eq("nested\n")
        expect(File.read("#{production_dir}/regular_file.txt")).to eq("hello\n")
      end
    end

    context 'when a modules directory exists in the current working directory' do
      it 'logs a warning' do
        repo = build_repo('deploy_test')

        allow(File).to receive(:directory?).and_call_original
        allow(File).to receive(:directory?).with('modules').and_return(true)

        expect(logger).to receive(:warn).with(/modules directory/)

        deploy.deploy_local(repo, { skip_r10k: true })
      end
    end

    context 'when a previous run left an onceover manifest behind' do
      it 'removes the files listed in the old manifest before copying the new tree' do
        repo = build_repo('deploy_test')
        production_dir = "#{tempdir}/#{repo.environmentpath}/production"
        FileUtils.mkdir_p(production_dir)
        stale_file = File.join(production_dir, 'stale_leftover.txt')
        File.write(stale_file, 'leftover')
        File.write(
          File.join(production_dir, '.onceover_manifest.json'),
          ['stale_leftover.txt'].to_json
        )

        deploy.deploy_local(repo, { skip_r10k: true })

        expect(File.exist?(stale_file)).to be false
      end
    end

    context 'when the Puppetfile references :control_branch' do
      it 'substitutes the current git branch in for :control_branch' do
        repo = build_repo('control_branch')

        allow(deploy).to receive(:system) do |_cmd|
          Kernel.system('true')
          true
        end

        deploy.deploy_local(repo, { skip_r10k: false })

        production_dir = "#{tempdir}/#{repo.environmentpath}/production"
        puppetfile_contents = File.read("#{production_dir}/Puppetfile")
        expect(puppetfile_contents).not_to include(':control_branch')
        current_branch = `git rev-parse --abbrev-ref HEAD`.chomp
        expect(puppetfile_contents).to include("'#{current_branch}'")
      end
    end

    context 'when auto_vendored is requested' do
      it 'asks VendoredModules for missing modules and appends them to the Puppetfile' do
        repo = build_repo('basic')

        vendored_modules_double = instance_double(
          'PuppetlabsOnceover::VendoredModules',
          missing_vendored: [{ 'puppetlabs-mymodule' => { git: 'https://example.com/mymodule.git', ref: 'main' } }]
        )
        allow(vendored_modules_double).to receive(:puppetfile_missing_vendored)
        allow(PuppetlabsOnceover::VendoredModules).to receive(:new).and_return(vendored_modules_double)

        allow(deploy).to receive(:system) do |_cmd|
          Kernel.system('true')
          true
        end

        deploy.deploy_local(repo, { skip_r10k: false, auto_vendored: true })

        production_dir = "#{tempdir}/#{repo.environmentpath}/production"
        puppetfile_contents = File.read("#{production_dir}/Puppetfile")
        expect(puppetfile_contents).to include('puppetlabs-mymodule')
        expect(puppetfile_contents).to include('PuppetlabsOnceover Managed Vendored Modules')
      end

      it 'leaves the Puppetfile untouched when there are no missing vendored modules' do
        repo = build_repo('basic')

        vendored_modules_double = instance_double(
          'PuppetlabsOnceover::VendoredModules',
          missing_vendored: []
        )
        allow(vendored_modules_double).to receive(:puppetfile_missing_vendored)
        allow(PuppetlabsOnceover::VendoredModules).to receive(:new).and_return(vendored_modules_double)

        allow(deploy).to receive(:system) do |_cmd|
          Kernel.system('true')
          true
        end

        deploy.deploy_local(repo, { skip_r10k: false, auto_vendored: true })

        production_dir = "#{tempdir}/#{repo.environmentpath}/production"
        puppetfile_contents = File.read("#{production_dir}/Puppetfile")
        expect(puppetfile_contents).not_to include('PuppetlabsOnceover Managed Vendored Modules')
      end
    end

    context 'when r10k succeeds' do
      it 'runs r10k puppetfile install and returns the tempdir, honoring force/config/trace/debug opts' do
        repo = build_repo('basic')
        allow(repo).to receive(:r10k_config_file).and_return('/tmp/some-r10k.yaml')
        logger.level = :debug

        seen_cmd = nil
        allow(deploy).to receive(:system) do |cmd|
          seen_cmd = cmd
          Kernel.system('true')
          true
        end

        result = deploy.deploy_local(repo, { skip_r10k: false, force: true, trace: true })

        expect(result).to eq(tempdir)
        expect(seen_cmd).to include('r10k puppetfile install --color')
        expect(seen_cmd).to include('--force')
        expect(seen_cmd).to include('--config /tmp/some-r10k.yaml')
        expect(seen_cmd).to include('--trace')
        expect(seen_cmd).to include('--verbose debug')

        logger.level = :info
      end

      it 'passes plain --verbose (not --verbose debug) when the logger is above debug level' do
        repo = build_repo('basic')
        logger.level = :info

        seen_cmd = nil
        allow(deploy).to receive(:system) do |cmd|
          seen_cmd = cmd
          Kernel.system('true')
          true
        end

        deploy.deploy_local(repo, { skip_r10k: false })

        expect(seen_cmd).to match(/--verbose(?! debug)/)
      end
    end

    context 'when r10k fails' do
      it 'raises an error' do
        repo = build_repo('basic')

        allow(deploy).to receive(:system) do |_cmd|
          Kernel.system('false')
          false
        end

        expect { deploy.deploy_local(repo, { skip_r10k: false }) }.to raise_error(
          'r10k could not install all required modules'
        )
      end
    end

    context 'when repo.tempdir is nil' do
      it 'creates a fresh tempdir via Dir.mktmpdir' do
        repo = build_repo('minimal', tempdir_override: nil)

        result = deploy.deploy_local(repo, {})

        expect(result).not_to be_nil
        expect(File.directory?(result)).to be true
        FileUtils.rm_rf(result)
      end
    end

    # NOTE: the `else raise "#{repo.tempdir} is not a directory"` branch
    # (deploy.rb, just after `if File.directory?(repo.tempdir)`) is left
    # uncovered. Reaching it legitimately requires repo.tempdir to vanish
    # between the copy step a few lines above and this check, and stubbing
    # File.directory?(repo.tempdir) to force it false also fools FileUtils'
    # own internal use of File.directory? earlier in the method (it calls
    # mkdir_p on a path it now believes doesn't exist, which raises
    # Errno::EEXIST instead of reaching the intended branch). Not worth
    # fighting with a source change out of scope for this test pass.
  end
end
