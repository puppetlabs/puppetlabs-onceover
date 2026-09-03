require 'spec_helper'
require 'puppetlabs-onceover/node'
require 'puppetlabs-onceover/controlrepo'

describe "PuppetlabsOnceover::Node" do
  before(:each) do
    PuppetlabsOnceover::Node.class_variable_set(:@@all, [])
    logger.level = :fatal
  end

  describe "#initialize" do
    context "when the controlrepo's factsets can be found" do
      before(:each) do
        PuppetlabsOnceover::Controlrepo.new(path: 'spec/fixtures/controlrepos/factsets')
      end

      it "sets the name and a nil beaker_node" do
        node = PuppetlabsOnceover::Node.new('centos7_notrusted')
        expect(node.name).to eq('centos7_notrusted')
        expect(node.beaker_node).to be_nil
      end

      it "loads the fact_set from the matching factset file" do
        node = PuppetlabsOnceover::Node.new('centos7_notrusted')
        expect(node.fact_set).to be_a(Hash)
        expect(node.fact_set['operatingsystem']).to eq('CentOS')
      end

      it "strips the 'environment' key out of the fact_set via clean_facts" do
        node = PuppetlabsOnceover::Node.new('centos_with_env')
        expect(node.fact_set).not_to have_key('environment')
      end

      it "finds a top-level 'trusted' hash for trusted_set" do
        node = PuppetlabsOnceover::Node.new('centos7_trusted_extensions_top')
        expect(node.trusted_set).to eq({ 'pp_datacenter' => 'PDX' })
      end

      it "falls back to a nested trusted.extensions hash for trusted_set when no top-level trusted hash exists" do
        node = PuppetlabsOnceover::Node.new('centos7_trusted_extensions_nested')
        expect(node.trusted_set).to be_a(Hash)
      end

      it "falls back to an empty hash for trusted_set when neither is present" do
        node = PuppetlabsOnceover::Node.new('centos7_notrusted')
        expect(node.trusted_set).to eq({})
      end

      it "falls back to a nested trusted.external hash for trusted_external_set when no top-level trusted_external hash exists" do
        node = PuppetlabsOnceover::Node.new('centos7_trusted_external_nested')
        expect(node.trusted_external_set).to be_a(Hash)
      end

      it "falls back to an empty hash for trusted_external_set when neither is present" do
        node = PuppetlabsOnceover::Node.new('centos7_notrusted')
        expect(node.trusted_external_set).to eq({})
      end

      it "adds itself to .all" do
        node = PuppetlabsOnceover::Node.new('centos7_notrusted')
        expect(PuppetlabsOnceover::Node.all).to eq([node])
      end
    end

    context "when no factset matches the given name" do
      before(:each) do
        PuppetlabsOnceover::Controlrepo.new(path: 'spec/fixtures/controlrepos/factsets')
      end

      # facts_file_index comes back nil, so PuppetlabsOnceover::Controlrepo.facts[nil]
      # raises TypeError -- this is the rescue branch that defaults everything to {}
      it "rescues the TypeError and defaults fact_set/trusted_set/trusted_external_set to {}" do
        node = PuppetlabsOnceover::Node.new('no_such_factset_anywhere')
        expect(node.fact_set).to eq({})
        expect(node.trusted_set).to eq({})
        expect(node.trusted_external_set).to eq({})
      end
    end
  end

  describe ".find" do
    before(:each) do
      PuppetlabsOnceover::Controlrepo.new(path: 'spec/fixtures/controlrepos/factsets')
    end

    it "finds a node by name" do
      node = PuppetlabsOnceover::Node.new('centos7_notrusted')
      expect(PuppetlabsOnceover::Node.find('centos7_notrusted')).to eq(node)
    end

    it "returns the same node object when passed a Node instance" do
      node = PuppetlabsOnceover::Node.new('centos7_notrusted')
      expect(PuppetlabsOnceover::Node.find(node)).to eq(node)
    end

    it "returns nil (and warns) when nothing matches" do
      expect(PuppetlabsOnceover::Node.find('nonexistent')).to be_nil
    end
  end

  describe ".all" do
    before(:each) do
      PuppetlabsOnceover::Controlrepo.new(path: 'spec/fixtures/controlrepos/factsets')
    end

    it "returns every node created so far" do
      a = PuppetlabsOnceover::Node.new('centos7_notrusted')
      b = PuppetlabsOnceover::Node.new('centos_with_env')
      expect(PuppetlabsOnceover::Node.all).to eq([a, b])
    end
  end

  describe ".clean_facts" do
    it "deletes the 'environment' key and returns the factset" do
      factset = { 'environment' => 'production', 'foo' => 'bar' }
      expect(PuppetlabsOnceover::Node.clean_facts(factset)).to eq({ 'foo' => 'bar' })
    end

    it "is a no-op when there is no 'environment' key" do
      factset = { 'foo' => 'bar' }
      expect(PuppetlabsOnceover::Node.clean_facts(factset)).to eq({ 'foo' => 'bar' })
    end
  end
end
