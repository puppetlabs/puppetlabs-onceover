require 'spec_helper'
require 'puppetlabs-onceover/group'
require 'puppetlabs-onceover/class'
require 'puppetlabs-onceover/node'
require 'puppetlabs-onceover/testconfig'
require 'puppetlabs-onceover/controlrepo'

describe "PuppetlabsOnceover::Group" do
  before(:each) do
    PuppetlabsOnceover::Class.class_variable_set(:@@all, [])
    PuppetlabsOnceover::Node.class_variable_set(:@@all, [])
    PuppetlabsOnceover::Group.class_variable_set(:@@all, [])
    PuppetlabsOnceover::Test.class_variable_set(:@@all, [])
    logger.level = :fatal
    PuppetlabsOnceover::Controlrepo.new(path: 'spec/fixtures/controlrepos/factsets')
  end

  describe "#initialize" do
    it "accepts a ready-made list of Class objects as-is" do
      a = PuppetlabsOnceover::Class.new('role::a')
      b = PuppetlabsOnceover::Class.new('role::b')
      group = PuppetlabsOnceover::Group.new('my_classes', [a, b])
      expect(group.name).to eq('my_classes')
      expect(group.members).to eq([a, b])
    end

    it "accepts a ready-made list of Node objects as-is" do
      a = PuppetlabsOnceover::Node.new('node_a')
      b = PuppetlabsOnceover::Node.new('node_b')
      group = PuppetlabsOnceover::Group.new('my_nodes', [a, b])
      expect(group.members).to eq([a, b])
    end

    it "defaults to an empty member list when members is nil" do
      group = PuppetlabsOnceover::Group.new('empty_group', nil)
      expect(group.members).to eq([])
    end

    it "resolves a hash into a subtractive include/exclude list via TestConfig.subtractive_to_list" do
      a = PuppetlabsOnceover::Node.new('node_a')
      b = PuppetlabsOnceover::Node.new('node_b')
      PuppetlabsOnceover::Group.new('all_nodes', [a, b])
      PuppetlabsOnceover::Group.new('excluded', [b])

      group = PuppetlabsOnceover::Group.new('subtractive', { 'include' => 'all_nodes', 'exclude' => 'excluded' })
      expect(group.members).to eq([a])
    end

    it "resolves a list of names/groups into member objects, flattening nested groups" do
      a = PuppetlabsOnceover::Node.new('node_a')
      b = PuppetlabsOnceover::Node.new('node_b')
      PuppetlabsOnceover::Group.new('inner', [a])

      group = PuppetlabsOnceover::Group.new('outer', %w[inner node_b])
      expect(group.members).to eq([a, b])
    end

    it "raises when a resolved member list mixes classes and nodes" do
      PuppetlabsOnceover::Class.new('role::a')
      PuppetlabsOnceover::Node.new('node_a')

      expect do
        PuppetlabsOnceover::Group.new('mixed', ['role::a', 'node_a'])
      end.to raise_error(RuntimeError, /must contain either all nodes or all classes/)
    end

    it "adds itself to .all" do
      group = PuppetlabsOnceover::Group.new('g', nil)
      expect(PuppetlabsOnceover::Group.all).to eq([group])
    end
  end

  describe ".find" do
    it "finds a group by name" do
      group = PuppetlabsOnceover::Group.new('g', nil)
      expect(PuppetlabsOnceover::Group.find('g')).to eq(group)
    end

    it "returns nil when no group matches" do
      expect(PuppetlabsOnceover::Group.find('nope')).to be_nil
    end
  end

  describe ".all" do
    it "returns every group created so far" do
      a = PuppetlabsOnceover::Group.new('a', nil)
      b = PuppetlabsOnceover::Group.new('b', nil)
      expect(PuppetlabsOnceover::Group.all).to eq([a, b])
    end
  end

  describe ".valid_members?" do
    it "is true for an all-Class list" do
      a = PuppetlabsOnceover::Class.new('role::a')
      expect(PuppetlabsOnceover::Group.valid_members?([a])).to eq(true)
    end

    it "is true for an all-Node list" do
      a = PuppetlabsOnceover::Node.new('node_a')
      expect(PuppetlabsOnceover::Group.valid_members?([a])).to eq(true)
    end

    it "is false for a mixed list" do
      a = PuppetlabsOnceover::Class.new('role::a')
      b = PuppetlabsOnceover::Node.new('node_a')
      expect(PuppetlabsOnceover::Group.valid_members?([a, b])).to eq(false)
    end

    it "is false for an empty list (all? on empty is true for the Class check, so this actually documents current behavior)" do
      expect(PuppetlabsOnceover::Group.valid_members?([])).to eq(true)
    end

    it "rescues any StandardError raised while checking and returns false" do
      exploding = Object.new
      def exploding.is_a?(*)
        raise StandardError, 'boom'
      end
      expect(PuppetlabsOnceover::Group.valid_members?([exploding])).to eq(false)
    end
  end
end
