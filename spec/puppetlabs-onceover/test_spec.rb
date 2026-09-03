require 'spec_helper'
require 'puppetlabs-onceover/test'
require 'puppetlabs-onceover/class'
require 'puppetlabs-onceover/node'
require 'puppetlabs-onceover/group'
require 'puppetlabs-onceover/testconfig'
require 'puppetlabs-onceover/controlrepo'

describe "PuppetlabsOnceover::Test" do
  before(:each) do
    PuppetlabsOnceover::Class.class_variable_set(:@@all, [])
    PuppetlabsOnceover::Node.class_variable_set(:@@all, [])
    PuppetlabsOnceover::Group.class_variable_set(:@@all, [])
    PuppetlabsOnceover::Test.class_variable_set(:@@all, [])
    logger.level = :fatal
    PuppetlabsOnceover::Controlrepo.new(path: 'spec/fixtures/controlrepos/factsets')
  end

  let(:node_a) { PuppetlabsOnceover::Node.new('node_a') }
  let(:node_b) { PuppetlabsOnceover::Node.new('node_b') }
  let(:class_a) { PuppetlabsOnceover::Class.new('role::a') }
  let(:class_b) { PuppetlabsOnceover::Class.new('role::b') }

  describe "#initialize" do
    it "merges in the default test_config (check_idempotency/runs_before_idempotency)" do
      test = PuppetlabsOnceover::Test.new(node_a.name, class_a, {})
      expect(test.test_config['check_idempotency']).to eq(true)
      expect(test.test_config['runs_before_idempotency']).to eq(1)
    end

    it "lets explicit test_config values override the defaults" do
      test = PuppetlabsOnceover::Test.new(node_a.name, class_a, { 'check_idempotency' => false })
      expect(test.test_config['check_idempotency']).to eq(false)
    end

    it "removes 'classes' from the stored test_config" do
      test = PuppetlabsOnceover::Test.new(node_a.name, class_a, { 'classes' => 'whatever' })
      expect(test.test_config).not_to have_key('classes')
    end

    it "normalizes a single tag string into an array" do
      test = PuppetlabsOnceover::Test.new(node_a.name, class_a, { 'tags' => 'sometag' })
      expect(test.tags).to eq(['sometag'])
    end

    it "leaves an array of tags as-is" do
      test = PuppetlabsOnceover::Test.new(node_a.name, class_a, { 'tags' => %w[a b] })
      expect(test.tags).to eq(%w[a b])
    end

    it "defaults tags to an empty array when absent" do
      test = PuppetlabsOnceover::Test.new(node_a.name, class_a, {})
      expect(test.tags).to eq([])
    end

    context "resolving the 'on_this' (node) argument" do
      it "accepts a group name and expands it to its member nodes" do
        PuppetlabsOnceover::Group.new('nodegroup', [node_a, node_b])
        test = PuppetlabsOnceover::Test.new('nodegroup', class_a, {})
        expect(test.nodes).to eq([node_a, node_b])
      end

      it "accepts a plain node name" do
        test = PuppetlabsOnceover::Test.new(node_a.name, class_a, {})
        expect(test.nodes).to eq([node_a])
      end

      it "raises when the node/group cannot be found" do
        expect do
          PuppetlabsOnceover::Test.new('no_such_node_or_group', class_a, {})
        end.to raise_error(RuntimeError, /was not found in the list of nodes or groups/)
      end
    end

    context "resolving the 'test_this' (classes) argument" do
      it "accepts a group name and expands it to its member classes" do
        PuppetlabsOnceover::Group.new('classgroup', [class_a, class_b])
        test = PuppetlabsOnceover::Test.new(node_a.name, 'classgroup', {})
        expect(test.classes).to eq([class_a, class_b])
      end

      it "accepts a plain class name" do
        test = PuppetlabsOnceover::Test.new(node_a.name, class_a.name, {})
        expect(test.classes).to eq([class_a])
      end

      it "raises when given a string that matches neither a class nor a group" do
        expect do
          PuppetlabsOnceover::Test.new(node_a.name, 'no_such_class_or_group', {})
        end.to raise_error(RuntimeError, /was not found in the list of classes or groups/)
      end

      it "accepts a subtractive include/exclude hash" do
        PuppetlabsOnceover::Group.new('all_classes', [class_a, class_b])
        PuppetlabsOnceover::Group.new('excluded', [class_b])
        test = PuppetlabsOnceover::Test.new(node_a.name, { 'include' => 'all_classes', 'exclude' => 'excluded' }, {})
        expect(test.classes).to eq([class_a])
      end

      it "accepts a Class object directly" do
        test = PuppetlabsOnceover::Test.new(node_a.name, class_a, {})
        expect(test.classes).to eq([class_a])
      end
    end
  end

  describe "#eql?" do
    it "is true when both nodes and classes match once sorted" do
      t1 = PuppetlabsOnceover::Test.new(node_a.name, class_a, {})
      t2 = PuppetlabsOnceover::Test.new(node_a.name, class_a, {})
      expect(t1.eql?(t2)).to eq(true)
    end

    it "is false when the classes differ" do
      t1 = PuppetlabsOnceover::Test.new(node_a.name, class_a, {})
      t2 = PuppetlabsOnceover::Test.new(node_a.name, class_b, {})
      expect(t1.eql?(t2)).to eq(false)
    end
  end

  describe "#to_s" do
    it "uses the singular class and node name when there is only one of each" do
      test = PuppetlabsOnceover::Test.new(node_a.name, class_a, {})
      expect(test.to_s).to eq("role__a_on_node_a")
    end

    it "summarizes as N_classes when there are multiple classes" do
      PuppetlabsOnceover::Group.new('classgroup', [class_a, class_b])
      test = PuppetlabsOnceover::Test.new(node_a.name, 'classgroup', {})
      expect(test.to_s).to eq("2_classes_on_node_a")
    end

    it "summarizes as N_nodes when there are multiple nodes" do
      PuppetlabsOnceover::Group.new('nodegroup', [node_a, node_b])
      test = PuppetlabsOnceover::Test.new('nodegroup', class_a, {})
      expect(test.to_s).to eq("role__a_on_2_nodes")
    end
  end

  describe ".deduplicate" do
    it "merges duplicate node/class combinations into a single test, keeping non-default config" do
      t1 = PuppetlabsOnceover::Test.new(node_a.name, class_a, {})
      t2 = PuppetlabsOnceover::Test.new(node_a.name, class_a, { 'check_idempotency' => false })

      deduped = PuppetlabsOnceover::Test.deduplicate([t1, t2])
      expect(deduped.length).to eq(1)
      expect(deduped.first.test_config['check_idempotency']).to eq(false)
    end

    it "leaves distinct node/class combinations as separate tests" do
      t1 = PuppetlabsOnceover::Test.new(node_a.name, class_a, {})
      t2 = PuppetlabsOnceover::Test.new(node_b.name, class_b, {})

      deduped = PuppetlabsOnceover::Test.deduplicate([t1, t2])
      expect(deduped.length).to eq(2)
    end

    it "handles tests with multiple nodes/classes by expanding every combination" do
      PuppetlabsOnceover::Group.new('nodegroup', [node_a, node_b])
      PuppetlabsOnceover::Group.new('classgroup', [class_a, class_b])
      t1 = PuppetlabsOnceover::Test.new('nodegroup', 'classgroup', {})

      deduped = PuppetlabsOnceover::Test.deduplicate([t1])
      # 2 nodes x 2 classes = 4 distinct combinations
      expect(deduped.length).to eq(4)
    end
  end

  describe ".all" do
    # Unlike Class/Node/Group, Test#initialize never appends `self` to @@all,
    # so .all is always empty in practice -- documenting actual behavior here.
    it "returns the (always empty) @@all class variable, since #initialize never appends to it" do
      PuppetlabsOnceover::Test.new(node_a.name, class_a, {})
      expect(PuppetlabsOnceover::Test.all).to eq([])
    end
  end
end
