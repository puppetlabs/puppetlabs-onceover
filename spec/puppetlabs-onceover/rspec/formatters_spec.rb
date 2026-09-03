require 'spec_helper'
require 'stringio'
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'puppetlabs-onceover/controlrepo'
require 'puppetlabs-onceover/rspec/formatters'

describe PuppetlabsOnceoverFormatter do
  let(:output) { StringIO.new }
  subject(:formatter) { described_class.new(output) }

  def group_double(description)
    group = double('group', description: description)
    allow(group).to receive(:parent_groups).and_return([group])
    group
  end

  def stub_world_groups(descriptions)
    groups = descriptions.map { |d| double('group', description: d) }
    allow(RSpec.configuration.world).to receive(:example_groups).and_return(groups)
  end

  def failure_double(role:, factset:, raw_error:, description: 'a test', file_path: '/spec/foo_spec.rb', line_number: 5)
    metadata = {
      example_group: {
        description: factset,
        parent_example_group: { description: role }
      },
      execution_result: double('execution_result', exception: RuntimeError.new(raw_error)),
      description: description,
      file_path: file_path,
      line_number: line_number
    }
    double('example', metadata: metadata)
  end

  describe '#example_group_started' do
    context 'when the group is a top-level role' do
      it 'prints the role name and sets previous_role' do
        stub_world_groups(['role::foo', 'role::barbaz'])
        group = group_double('role::foo')
        notification = double('notification', group: group)

        formatter.example_group_started(notification)

        expect(output.string).to include('role::foo:')
      end

      it 'does not reprint the same role twice in a row' do
        stub_world_groups(['role::foo'])
        group = group_double('role::foo')
        notification = double('notification', group: group)

        formatter.example_group_started(notification)
        first_output = output.string
        formatter.example_group_started(notification)

        expect(output.string).to eq(first_output)
      end
    end

    context 'when the group is nested (not the top-level role)' do
      it "prints '? ' as a placeholder" do
        top = double('top_group')
        group = double('group', description: 'nested context')
        allow(group).to receive(:parent_groups).and_return([top, group])
        notification = double('notification', group: group)

        formatter.example_group_started(notification)

        expect(output.string).to eq('? ')
      end
    end
  end

  describe '#example_passed' do
    it 'writes a green P' do
      formatter.example_passed(double('notification'))
      expect(output.string).to include('P')
    end
  end

  describe '#example_failed' do
    it 'writes a red F' do
      formatter.example_failed(double('notification'))
      expect(output.string).to include('F')
    end
  end

  describe '#example_pending' do
    it 'writes a yellow ?' do
      formatter.example_pending(double('notification'))
      expect(output.string).to include('?')
    end
  end

  describe '#parse_errors' do
    it 'parses a compilation error with a file/line/column location' do
      allow(RSpec.configuration).to receive(:onceover_tempdir).and_return('/tmp/xyz/.onceover')
      allow(RSpec.configuration).to receive(:onceover_root).and_return('/tmp/xyz')
      allow(RSpec.configuration).to receive(:onceover_environmentpath).and_return('etc/puppetlabs/code/environments')

      raw = 'Some function failed error during compilation: bad value at (file: /tmp/xyz/.onceover/etc/puppetlabs/code/environments/production/site/role/manifests/foo.pp, line: 4, column: 2); more'
      results = formatter.parse_errors(raw)
      expect(results.first[:line]).to eq('4')
      expect(results.first[:column]).to eq('2')
      expect(results.first[:file]).to eq('site/role/manifests/foo.pp')
    end

    it 'parses a compilation error whose location omits the file' do
      raw = 'error during compilation: bad value at (line: 9, column: 1); trailer'
      results = formatter.parse_errors(raw)
      expect(results.first[:file]).to be_nil
      expect(results.first[:line]).to eq('9')
    end

    it 'parses a compilation error with no location at all, matching "on node"' do
      raw = 'error during compilation: something bad happened on node foo.example.com'
      results = formatter.parse_errors(raw)
      expect(results.first[:text]).to eq('something bad happened')
      expect(results.first[:file]).to be_nil
    end

    it 'falls back to the raw string when a compilation error matches neither location pattern' do
      raw = 'error during compilation: nothing structured here whatsoever'
      results = formatter.parse_errors(raw)
      expect(results).to eq([{ text: raw }])
    end

    it 'falls back to the raw string for a non-compilation error' do
      raw = "NoMethodError: undefined method 'foo' for nil"
      results = formatter.parse_errors(raw)
      expect(results).to eq([{ text: raw }])
    end
  end

  describe '#calculate_relative_source' do
    before do
      allow(RSpec.configuration).to receive(:onceover_tempdir).and_return('/tmp/xyz/.onceover')
      allow(RSpec.configuration).to receive(:onceover_root).and_return('/tmp/xyz')
      allow(RSpec.configuration).to receive(:onceover_environmentpath).and_return('etc/puppetlabs/code/environments')
    end

    it 'returns nil when given a nil file' do
      expect(formatter.calculate_relative_source(nil)).to be_nil
    end

    it 'calculates the path relative to the production environment root' do
      file = '/tmp/xyz/.onceover/etc/puppetlabs/code/environments/production/site/role/manifests/foo.pp'
      expect(formatter.calculate_relative_source(file)).to eq('site/role/manifests/foo.pp')
    end
  end

  describe '#extract_failure_data' do
    it 'attaches the list of failing factsets to each parsed error' do
      fails = [
        failure_double(role: 'role::foo', factset: 'using fact set centos-7-x86_64', raw_error: 'boom'),
        failure_double(role: 'role::foo', factset: 'using fact set windows-2019-x64', raw_error: 'boom')
      ]
      results = formatter.extract_failure_data(fails)
      expect(results.first[:factsets]).to eq(['centos-7-x86_64', 'windows-2019-x64'])
    end
  end

  describe '#extract_failures' do
    it 'groups failures by role and then by distinct error message' do
      notification = double(
        'notification',
        failed_examples: [
          failure_double(role: 'role::foo', factset: 'using fact set centos-7-x86_64', raw_error: 'boom one'),
          failure_double(role: 'role::foo', factset: 'using fact set windows-2019-x64', raw_error: 'boom two'),
          failure_double(role: 'role::bar', factset: 'using fact set centos-7-x86_64', raw_error: 'boom three')
        ]
      )

      grouped = formatter.extract_failures(notification)

      expect(grouped.keys).to contain_exactly('role::foo', 'role::bar')
      expect(grouped['role::foo'].size).to eq(2)
      expect(grouped['role::bar'].size).to eq(1)
    end
  end

  describe '#dump_failures' do
    before do
      allow(RSpec.configuration).to receive(:onceover_tempdir).and_return('/tmp/xyz/.onceover')
      allow(RSpec.configuration).to receive(:onceover_root).and_return('/tmp/xyz')
      allow(RSpec.configuration).to receive(:onceover_environmentpath).and_return('etc/puppetlabs/code/environments')
    end

    it 'renders the error summary template for each failing role' do
      notification = double(
        'notification',
        failed_examples: [
          failure_double(role: 'role::foo', factset: 'using fact set centos-7-x86_64', raw_error: 'boom')
        ]
      )

      formatter.dump_failures(notification)

      expect(output.string).to include('role::foo')
      expect(output.string).to include('failed')
    end
  end

  describe '#longest_group' do
    it 'returns the length of the longest example group description' do
      stub_world_groups(['role::a', 'role::much_longer_name'])
      expect(formatter.longest_group).to eq('role::much_longer_name'.length)
    end
  end

  describe 'color helper methods' do
    [:class_name, :black, :red, :green, :yellow, :blue, :magenta, :cyan, :white, :bold].each do |method|
      it "##{method} wraps the given text" do
        expect(formatter.public_send(method, 'hello')).to be_a(String)
        expect(formatter.public_send(method, 'hello')).to include('hello')
      end
    end
  end
end

describe PuppetlabsOnceoverFormatterParallel do
  let(:output) { StringIO.new }
  subject(:formatter) { described_class.new(output) }

  def failure_double(role:, factset:, raw_error:)
    metadata = {
      example_group: {
        description: factset,
        parent_example_group: { description: role }
      },
      execution_result: double('execution_result', exception: RuntimeError.new(raw_error))
    }
    double('example', metadata: metadata)
  end

  describe '#example_group_started' do
    it 'does nothing' do
      expect { formatter.example_group_started(double('notification')) }.not_to raise_error
      expect(output.string).to eq('')
    end
  end

  describe '#example_passed' do
    it 'writes and flushes a green P' do
      formatter.example_passed(double('notification'))
      expect(output.string).to include('P')
    end
  end

  describe '#example_failed' do
    it 'writes and flushes a red F' do
      formatter.example_failed(double('notification'))
      expect(output.string).to include('F')
    end
  end

  describe '#example_pending' do
    it 'writes and flushes a yellow ?' do
      formatter.example_pending(double('notification'))
      expect(output.string).to include('?')
    end
  end

  describe '#dump_failures' do
    it 'dumps a yaml file of the failures into the parallel results dir' do
      tempdir = Dir.mktmpdir
      allow(RSpec.configuration).to receive(:onceover_tempdir).and_return(tempdir)

      notification = double(
        'notification',
        failed_examples: [failure_double(role: 'role::foo', factset: 'using fact set centos-7-x86_64', raw_error: 'boom')]
      )

      formatter.dump_failures(notification)

      files = Dir["#{tempdir}/parallel/*.yaml"]
      expect(files.size).to eq(1)
      expect(YAML.load_file(files.first)).to have_key('role::foo')

      FileUtils.remove_entry(tempdir)
    end
  end

  describe '#output_results' do
    before do
      allow(RSpec.configuration).to receive(:onceover_tempdir).and_return('/tmp/xyz/.onceover')
      allow(RSpec.configuration).to receive(:onceover_root).and_return('/tmp/xyz')
      allow(RSpec.configuration).to receive(:onceover_environmentpath).and_return('etc/puppetlabs/code/environments')
    end

    it 'merges all yaml result files, renders them, and deletes the source files' do
      directory = Dir.mktmpdir
      File.write(File.join(directory, 'results-1.yaml'), { 'role::foo' => [{ text: 'boom one' }] }.to_yaml)
      File.write(File.join(directory, 'results-2.yaml'), { 'role::bar' => [{ text: 'boom two' }] }.to_yaml)

      formatter.output_results(directory)

      expect(output.string).to include('role::foo')
      expect(output.string).to include('role::bar')
      expect(Dir["#{directory}/*.yaml"]).to be_empty

      FileUtils.remove_entry(directory)
    end

    it 'merges values when the same role appears in multiple files' do
      directory = Dir.mktmpdir
      File.write(File.join(directory, 'results-1.yaml'), { 'role::foo' => [{ text: 'boom one' }] }.to_yaml)
      File.write(File.join(directory, 'results-2.yaml'), { 'role::foo' => [{ text: 'boom two' }] }.to_yaml)

      formatter.output_results(directory)

      expect(output.string).to include('role::foo')

      FileUtils.remove_entry(directory)
    end
  end
end

describe FailureCollector do
  let(:tempdir) { Dir.mktmpdir }

  before do
    allow(RSpec.configuration).to receive(:onceover_tempdir).and_return(tempdir)
  end

  after { FileUtils.rm_rf(tempdir) }

  describe '#initialize' do
    it 'touches a failures.out file in the onceover tempdir' do
      described_class.new(StringIO.new)
      expect(File.exist?(File.join(tempdir, 'failures.out'))).to be true
    end
  end

  describe '#dump_failures' do
    it 'appends details of each failed example to failures.out' do
      collector = described_class.new(StringIO.new)

      fe = double(
        'failed_example',
        metadata: {
          description: 'does a thing',
          execution_result: double('execution_result', exception: RuntimeError.new('kaboom')),
          file_path: '/spec/foo_spec.rb',
          line_number: 12
        }
      )
      failures = double('failures', failed_examples: [fe])

      collector.dump_failures(failures)

      contents = File.read(File.join(tempdir, 'failures.out'))
      expect(contents).to include('does a thing')
      expect(contents).to include('kaboom')
      expect(contents).to include('/spec/foo_spec.rb:12')
    end
  end
end
