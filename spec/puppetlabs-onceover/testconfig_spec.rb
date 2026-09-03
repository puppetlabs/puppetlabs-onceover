require 'spec_helper'
require 'puppetlabs-onceover/testconfig'
require 'puppetlabs-onceover/controlrepo'
require 'tempfile'
require 'tmpdir'
require 'yaml'
require 'fileutils'

describe "PuppetlabsOnceover::TestConfig" do
  before(:each) do
    PuppetlabsOnceover::Class.class_variable_set(:@@all, [])
    PuppetlabsOnceover::Node.class_variable_set(:@@all, [])
    PuppetlabsOnceover::Group.class_variable_set(:@@all, [])
    PuppetlabsOnceover::Test.class_variable_set(:@@all, [])
    logger.level = :fatal
    # Silence the deprecation warnings printed by the deprecated methods under test,
    # they're expected noise, not something we're asserting on.
  end

  # Helper to write an arbitrary onceover.yaml-shaped hash out to a real tempfile,
  # since some branches (malformed YAML, missing 'type' deprecation, all_tests, etc.)
  # aren't exercised by any checked-in fixture.
  def write_yaml(hash)
    file = Tempfile.new(['onceover', '.yaml'])
    file.write(hash.to_yaml)
    file.close
    file.path
  end

  let(:function_mocking_repo) do
    PuppetlabsOnceover::Controlrepo.new(path: 'spec/fixtures/controlrepos/function_mocking')
  end

  let(:puppet_controlrepo) do
    PuppetlabsOnceover::Controlrepo.new(
      path: File.expand_path('spec/fixtures/controlrepos/puppet_controlrepo'),
      tempdir: Dir.mktmpdir('onceover-testconfig-spec')
    )
  end

  describe "#initialize" do
    it "raises a friendly error when the file does not exist" do
      expect do
        PuppetlabsOnceover::TestConfig.new('spec/fixtures/controlrepos/does_not_exist/onceover.yaml')
      end.to raise_error(RuntimeError, /Could not find/)
    end

    it "raises a friendly error when the YAML is malformed" do
      file = Tempfile.new(['bad', '.yaml'])
      file.write("classes: [\nnodes: not: valid: :yaml")
      file.close

      expect do
        PuppetlabsOnceover::TestConfig.new(file.path)
      end.to raise_error(RuntimeError, /Could not parse/)
    end

    it "loads classes/nodes/groups/test_matrix from a real onceover.yaml, expanding regex classes via the controlrepo" do
      function_mocking_repo
      config = PuppetlabsOnceover::TestConfig.new('spec/fixtures/controlrepos/function_mocking/spec/onceover.yaml')

      expect(config.classes).not_to be_empty
      expect(config.classes.map(&:name)).to all(match(/role::/))
      expect(config.nodes.map(&:name)).to eq(['CentOS-7.0-64'])
      expect(config.spec_tests).not_to be_empty
      expect(config.acceptance_tests).to eq([])
    end

    it "builds the default 'all_nodes'/'all_classes' groups even with no explicit node_groups/class_groups" do
      function_mocking_repo
      config = PuppetlabsOnceover::TestConfig.new('spec/fixtures/controlrepos/function_mocking/spec/onceover.yaml')
      expect(config.node_groups.map(&:name)).to include('all_nodes')
      expect(config.class_groups.map(&:name)).to include('all_classes')
    end

    it "builds subtractive node_groups and populates both spec_tests and acceptance_tests" do
      puppet_controlrepo
      # caching's yaml has a subtractive-free node_group but a class_groups subtraction and both
      # 'spec' and no acceptance -- use the puppet_controlrepo yaml instead, which has a
      # subtractive class_group (linux_classes) and tags.
      config = PuppetlabsOnceover::TestConfig.new('spec/fixtures/controlrepos/puppet_controlrepo/spec/onceover.yaml')
      expect(config.class_groups.map(&:name)).to include('linux_classes')
      expect(config.spec_tests).not_to be_empty
      # the 'master' matrix entry sets a tag
      master_test = config.spec_tests.find { |t| t.tags.include?('master') }
      expect(master_test).not_to be_nil
    end

    it "builds both acceptance_tests and spec_tests from an 'all_tests' matrix entry" do
      function_mocking_repo
      yaml_path = write_yaml(
        'classes' => ['role::test_data_return'],
        'nodes' => ['CentOS-7.0-64'],
        'test_matrix' => [
          { 'all_nodes' => { 'classes' => 'all_classes', 'tests' => 'all_tests' } }
        ]
      )
      config = PuppetlabsOnceover::TestConfig.new(yaml_path)
      expect(config.spec_tests).not_to be_empty
      expect(config.acceptance_tests).not_to be_empty
      expect(config.spec_tests).to eq(config.acceptance_tests)
    end

    it "populates only acceptance_tests from an 'acceptance' matrix entry" do
      function_mocking_repo
      yaml_path = write_yaml(
        'classes' => ['role::test_data_return'],
        'nodes' => ['CentOS-7.0-64'],
        'test_matrix' => [
          { 'all_nodes' => { 'classes' => 'all_classes', 'tests' => 'acceptance' } }
        ]
      )
      config = PuppetlabsOnceover::TestConfig.new(yaml_path)
      expect(config.spec_tests).to eq([])
      expect(config.acceptance_tests).not_to be_empty
    end

    it "warns about the deprecated 'type' key on mocked functions but still loads them" do
      function_mocking_repo
      yaml_path = write_yaml(
        'classes' => ['role::test_data_return'],
        'nodes' => ['CentOS-7.0-64'],
        'test_matrix' => [{ 'all_nodes' => { 'classes' => 'all_classes', 'tests' => 'spec' } }],
        'functions' => { 'myfunc' => { 'type' => 'ruby', 'returns' => 'foo' } }
      )
      expect(logger).to receive(:warn).with(/'type' key for mocked functions is deprecated/)
      config = PuppetlabsOnceover::TestConfig.new(yaml_path)
      expect(config.mock_functions).to have_key('myfunc')
    end

    it "sets filter_tags/filter_classes/filter_nodes/skip_r10k/force/fail_fast from opts" do
      function_mocking_repo
      config = PuppetlabsOnceover::TestConfig.new(
        'spec/fixtures/controlrepos/function_mocking/spec/onceover.yaml',
        tags: 'foo,bar', classes: 'role::test_data_return', nodes: 'CentOS-7.0-64',
        skip_r10k: true, force: true, fail_fast: true
      )
      expect(config.filter_tags).to eq(%w[foo bar])
      expect(config.filter_classes.map(&:name)).to eq(['role::test_data_return'])
      expect(config.filter_nodes.map(&:name)).to eq(['CentOS-7.0-64'])
      expect(config.skip_r10k).to eq(true)
      expect(config.force).to eq(true)
      expect(config.fail_fast).to eq(true)
    end

    it "defaults skip_r10k/force/fail_fast to false when opts don't set them" do
      function_mocking_repo
      config = PuppetlabsOnceover::TestConfig.new('spec/fixtures/controlrepos/function_mocking/spec/onceover.yaml')
      expect(config.skip_r10k).to eq(false)
      expect(config.force).to eq(false)
      expect(config.fail_fast).to eq(false)
      expect(config.filter_tags).to be_nil
      expect(config.filter_classes).to be_nil
      expect(config.filter_nodes).to be_nil
    end

    it "defaults formatters based on :parallel when opts[:format] is [:defaults]" do
      function_mocking_repo
      config = PuppetlabsOnceover::TestConfig.new(
        'spec/fixtures/controlrepos/function_mocking/spec/onceover.yaml',
        format: [:defaults]
      )
      expect(config.formatters).to eq(['PuppetlabsOnceoverFormatter'])

      config_parallel = PuppetlabsOnceover::TestConfig.new(
        'spec/fixtures/controlrepos/function_mocking/spec/onceover.yaml',
        format: [:defaults], parallel: true
      )
      expect(config_parallel.formatters).to eq(['PuppetlabsOnceoverFormatterParallel'])
    end

    it "uses an explicit :format option verbatim when given" do
      function_mocking_repo
      config = PuppetlabsOnceover::TestConfig.new(
        'spec/fixtures/controlrepos/function_mocking/spec/onceover.yaml',
        format: ['documentation']
      )
      expect(config.formatters).to eq(['documentation'])
    end

    it "sets strict_variables based on opts[:strict_variables]" do
      function_mocking_repo
      yes_config = PuppetlabsOnceover::TestConfig.new(
        'spec/fixtures/controlrepos/function_mocking/spec/onceover.yaml', strict_variables: true
      )
      no_config = PuppetlabsOnceover::TestConfig.new(
        'spec/fixtures/controlrepos/function_mocking/spec/onceover.yaml', strict_variables: false
      )
      expect(yes_config.strict_variables).to eq('yes')
      expect(no_config.strict_variables).to eq('no')
    end
  end

  describe "#to_s" do
    it "renders a colorized summary" do
      function_mocking_repo
      config = PuppetlabsOnceover::TestConfig.new('spec/fixtures/controlrepos/function_mocking/spec/onceover.yaml')
      expect(config.to_s).to include('classes')
      expect(config.to_s).to include('CentOS-7.0-64')
    end
  end

  describe ".find_list" do
    before(:each) { function_mocking_repo }

    it "finds a group's members" do
      a = PuppetlabsOnceover::Node.new('node_a')
      PuppetlabsOnceover::Group.new('mygroup', [a])
      expect(PuppetlabsOnceover::TestConfig.find_list('mygroup')).to eq([a])
    end

    it "wraps a single class match in an array" do
      cls = PuppetlabsOnceover::Class.new('role::a')
      expect(PuppetlabsOnceover::TestConfig.find_list('role::a')).to eq([cls])
    end

    it "wraps a single node match in an array" do
      node = PuppetlabsOnceover::Node.new('node_a')
      expect(PuppetlabsOnceover::TestConfig.find_list('node_a')).to eq([node])
    end

    it "raises when nothing matches, and restores the logger level afterwards" do
      logger.level = :info
      expect do
        PuppetlabsOnceover::TestConfig.find_list('totally_unknown_thing')
      end.to raise_error(RuntimeError, /Could not find totally_unknown_thing/)
      expect(logger.level).to eq(1) # :info
    end
  end

  describe ".subtractive_to_list" do
    before(:each) { function_mocking_repo }

    it "subtracts the exclude list's members from the include list's members" do
      a = PuppetlabsOnceover::Node.new('node_a')
      b = PuppetlabsOnceover::Node.new('node_b')
      PuppetlabsOnceover::Group.new('all', [a, b])
      PuppetlabsOnceover::Group.new('excluded', [b])

      result = PuppetlabsOnceover::TestConfig.subtractive_to_list('include' => 'all', 'exclude' => 'excluded')
      expect(result).to eq([a])
    end

    it "raises when 'exclude' is missing" do
      expect do
        PuppetlabsOnceover::TestConfig.subtractive_to_list('include' => 'all')
      end.to raise_error(RuntimeError, /must have an `exclude`/)
    end

    it "raises when 'include' is missing" do
      expect do
        PuppetlabsOnceover::TestConfig.subtractive_to_list('exclude' => 'all')
      end.to raise_error(RuntimeError, /must have an `exclude`/)
    end
  end

  describe "#verify_spec_test" do
    let!(:repo) { function_mocking_repo }
    let(:config) { PuppetlabsOnceover::TestConfig.new('spec/fixtures/controlrepos/function_mocking/spec/onceover.yaml') }

    it "does not raise when a factset exists for every node in the test" do
      test = config.spec_tests.first
      expect { config.verify_spec_test(repo, test) }.not_to raise_error
    end

    it "raises when a node's factset cannot be found" do
      missing_node = PuppetlabsOnceover::Node.new('totally_missing_node')
      fake_test = double('test', nodes: [missing_node])
      expect { config.verify_spec_test(repo, fake_test) }.to raise_error(RuntimeError, /Could not find factset/)
    end
  end

  describe "#verify_acceptance_test" do
    let!(:repo) { puppet_controlrepo }
    let(:config) { PuppetlabsOnceover::TestConfig.new('spec/fixtures/controlrepos/puppet_controlrepo/spec/onceover.yaml') }

    it "warns about deprecation, and does not raise when the node is in the nodeset" do
      config # force TestConfig#initialize to run first, populating Node.all
      node = PuppetlabsOnceover::Node.find('CentOS-7.0-64')
      test = double('test', nodes: [node])
      expect { config.verify_acceptance_test(repo, test) }.to output(/DEPRECATION/).to_stderr
    end

    it "raises when the node is not present in the nodeset file" do
      config
      missing_node = PuppetlabsOnceover::Node.new('totally_missing_node')
      test = double('test', nodes: [missing_node])
      expect { config.verify_acceptance_test(repo, test) }.to raise_error(RuntimeError, /Could not find nodeset/)
    end
  end

  describe "#pre_condition" do
    it "concatenates every *.pp file under spec/pre_conditions into one string" do
      puppet_controlrepo
      config = PuppetlabsOnceover::TestConfig.new(
        'spec/fixtures/controlrepos/puppet_controlrepo/spec/onceover.yaml',
        path: 'spec/fixtures/controlrepos/puppet_controlrepo'
      )
      result = config.pre_condition
      expect(result).to be_a(String)
      expect(result).to include('puppet_enterprise')
    end

    it "returns nil when there are no pre_condition files" do
      function_mocking_repo
      config = PuppetlabsOnceover::TestConfig.new(
        'spec/fixtures/controlrepos/function_mocking/spec/onceover.yaml',
        path: 'spec/fixtures/controlrepos/function_mocking'
      )
      expect(config.pre_condition).to be_nil
    end
  end

  describe "writer methods" do
    let!(:repo) { puppet_controlrepo }
    let(:config) do
      PuppetlabsOnceover::TestConfig.new(
        'spec/fixtures/controlrepos/puppet_controlrepo/spec/onceover.yaml',
        path: repo.root
      )
    end
    let(:location) { Dir.mktmpdir('onceover-testconfig-writer-spec') }

    it "#write_spec_test renders a spec file for a test" do
      test = config.spec_tests.first
      config.write_spec_test(location, test)
      expect(File.exist?("#{location}/#{test}_spec.rb")).to eq(true)
    end

    it "#write_acceptance_tests warns about deprecation and renders acceptance_spec.rb" do
      expect { config.write_acceptance_tests(location, config.spec_tests) }.to output(/DEPRECATION/).to_stderr
      expect(File.exist?("#{location}/acceptance_spec.rb")).to eq(true)
    end

    it "#write_spec_helper_acceptance renders spec_helper_acceptance.rb" do
      config.write_spec_helper_acceptance(location, repo)
      expect(File.exist?("#{location}/spec_helper_acceptance.rb")).to eq(true)
    end

    it "#write_rakefile renders a Rakefile" do
      config.write_rakefile(location, 'spec/**/*_spec.rb')
      expect(File.exist?("#{location}/Rakefile")).to eq(true)
    end

    it "#write_spec_helper renders spec_helper.rb, mutating repo.temp_modulepath as a side effect" do
      config.write_spec_helper(location, repo)
      expect(File.exist?("#{location}/spec_helper.rb")).to eq(true)
      expect(repo.temp_modulepath).to include(repo.tempdir)
    end
  end

  describe "#copy_spec_files" do
    it "copies every file matching the included_specs glob from repo.spec_dir into repo.tempdir/spec" do
      repo = puppet_controlrepo
      config = PuppetlabsOnceover::TestConfig.new('spec/fixtures/controlrepos/puppet_controlrepo/spec/onceover.yaml')
      # In the real flow write_spec_helper (or similar) creates this dir first; the production
      # copy_spec_files code only mkdir_p's for individual *files*, not for directory entries
      # encountered before any file inside them, so we replicate that ordering here.
      FileUtils.mkdir_p("#{repo.tempdir}/spec")
      config.copy_spec_files(repo)
      expect(File.exist?("#{repo.tempdir}/spec/onceover.yaml")).to eq(true)
    end

    it "respects a custom include_spec_files glob from the yaml" do
      repo = function_mocking_repo
      yaml_path = write_yaml(
        'classes' => ['role::test_data_return'],
        'nodes' => ['CentOS-7.0-64'],
        'test_matrix' => [{ 'all_nodes' => { 'classes' => 'all_classes', 'tests' => 'spec' } }],
        'include_spec_files' => 'onceover.yaml'
      )
      config = PuppetlabsOnceover::TestConfig.new(yaml_path, path: 'spec/fixtures/controlrepos/function_mocking',
                                                             tempdir: Dir.mktmpdir('onceover-copy-spec'))
      config.copy_spec_files(repo)
      expect(File.exist?("#{repo.tempdir}/spec/onceover.yaml")).to eq(true)
    end
  end

  describe "#create_fixtures_symlinks" do
    # NOTE: the File::ALT_SEPARATOR branch inside create_fixtures_symlinks (the
    # Dir.create_junction / `mklink /J` Windows-junction path) can't be exercised
    # here -- File::ALT_SEPARATOR is only ever truthy when Ruby itself is running
    # on Windows, which this suite does not run on. Left uncovered deliberately;
    # the non-Windows FileUtils.ln_s branch below is what we actually cover.
    it "symlinks every module on the temp_modulepath into repo.tempdir/spec/fixtures/modules" do
      repo = puppet_controlrepo
      config = PuppetlabsOnceover::TestConfig.new(
        'spec/fixtures/controlrepos/puppet_controlrepo/spec/onceover.yaml',
        path: repo.root
      )
      location = "#{repo.tempdir}/spec"
      FileUtils.mkdir_p(location)
      config.write_spec_helper(location, repo)

      # Normally r10k would have deployed real module content under the tempdir's
      # environmentpath before this step runs; simulate that with a dummy module dir.
      dummy_module_dir = "#{repo.temp_modulepath.split(':').first}/dummymodule"
      FileUtils.mkdir_p(dummy_module_dir)

      config.create_fixtures_symlinks(repo)

      links = Dir["#{repo.tempdir}/spec/fixtures/modules/*"]
      expect(links).not_to be_empty
      expect(File.symlink?(links.first)).to eq(true)
    end
  end

  describe "#run_filters and #filter_test" do
    let!(:repo) { function_mocking_repo }
    let!(:config) { PuppetlabsOnceover::TestConfig.new('spec/fixtures/controlrepos/function_mocking/spec/onceover.yaml') }

    it "returns every test untouched when no filters are configured" do
      tests = config.spec_tests.dup
      expect(config.run_filters(tests.dup)).to eq(tests)
    end

    it "keeps only tests whose classes match filter_classes" do
      config.filter_classes = [PuppetlabsOnceover::Class.find('role::test_data_return')]
      config.filter_tags = nil
      config.filter_nodes = nil
      filtered = config.run_filters(config.spec_tests.dup)
      expect(filtered).to all(satisfy { |t| t.classes.include?(config.filter_classes.first) })
    end

    it "keeps only tests whose nodes match filter_nodes" do
      config.filter_nodes = [PuppetlabsOnceover::Node.find('CentOS-7.0-64')]
      filtered = config.run_filters(config.spec_tests.dup)
      expect(filtered).to all(satisfy { |t| t.nodes.include?(config.filter_nodes.first) })
    end

    it "keeps only tests whose tags match filter_tags" do
      test_with_tag = PuppetlabsOnceover::Test.new('CentOS-7.0-64', 'role::test_data_return', 'tags' => 'important')
      config.filter_tags = ['important']
      filtered = config.run_filters([test_with_tag])
      expect(filtered).to eq([test_with_tag])
    end

    it "excludes tests whose tag matches a negated (~) filter" do
      test_with_tag = PuppetlabsOnceover::Test.new('CentOS-7.0-64', 'role::test_data_return', 'tags' => 'skip_me')
      config.filter_tags = ['~skip_me']
      filtered = config.run_filters([test_with_tag])
      expect(filtered).to eq([])
    end

    it "#filter_test returns false when the test has no value at all for that method" do
      test_without_tags = PuppetlabsOnceover::Test.new('CentOS-7.0-64', 'role::test_data_return', {})
      allow(test_without_tags).to receive(:tags).and_return(nil)
      expect(config.filter_test(test_without_tags, 'tags', 'anything')).to eq(false)
    end
  end
end
