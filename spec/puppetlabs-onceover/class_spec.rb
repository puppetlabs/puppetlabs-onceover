require 'spec_helper'
require 'puppetlabs-onceover/class'
require 'puppetlabs-onceover/controlrepo'

describe "PuppetlabsOnceover::Class" do
  before(:each) do
    PuppetlabsOnceover::Class.class_variable_set(:@@all, [])
    # Silence the info/warn logging noise from the shared $logger global
    logger.level = :fatal
  end

  describe ".name_is_regexp?" do
    it "returns true for a /.../ delimited string" do
      expect(PuppetlabsOnceover::Class.name_is_regexp?('/role::/')).to eq(true)
    end

    it "returns false for a plain string" do
      expect(PuppetlabsOnceover::Class.name_is_regexp?('role::webserver')).to eq(false)
    end

    it "returns false for a string that only starts with /" do
      expect(PuppetlabsOnceover::Class.name_is_regexp?('/role::webserver')).to eq(false)
    end
  end

  describe ".string_to_regexp" do
    it "converts a /.../ delimited string into a Regexp" do
      expect(PuppetlabsOnceover::Class.string_to_regexp('/role::/')).to eq(Regexp.new('role::'))
    end

    it "raises when the string is not regexp-shaped" do
      expect { PuppetlabsOnceover::Class.string_to_regexp('role::webserver') }.to raise_error(
        RuntimeError, /does not start and end with/
      )
    end
  end

  describe "#initialize" do
    it "sets the name and adds itself to .all for a plain class name" do
      cls = PuppetlabsOnceover::Class.new('role::webserver')
      expect(cls.name).to eq('role::webserver')
      expect(PuppetlabsOnceover::Class.all).to eq([cls])
    end

    context "when given a regexp name" do
      before(:each) do
        PuppetlabsOnceover::Controlrepo.new(path: 'spec/fixtures/controlrepos/function_mocking')
      end

      it "expands into one Class object per matching controlrepo class, and does not add the regexp itself" do
        PuppetlabsOnceover::Class.new('/role::/')
        names = PuppetlabsOnceover::Class.all.map(&:name)
        expect(names).not_to be_empty
        expect(names).to all(match(/role::/))
      end

      it "creates no objects when nothing matches" do
        PuppetlabsOnceover::Class.new('/nothing_matches_this_prefix_xyz::/')
        expect(PuppetlabsOnceover::Class.all).to eq([])
      end
    end
  end

  describe ".find" do
    it "finds an exact match by name" do
      cls = PuppetlabsOnceover::Class.new('role::webserver')
      expect(PuppetlabsOnceover::Class.find('role::webserver')).to eq(cls)
    end

    it "returns nil (and warns) when nothing matches" do
      expect(PuppetlabsOnceover::Class.find('role::does_not_exist')).to be_nil
    end

    it "finds all matches when given a regexp name" do
      a = PuppetlabsOnceover::Class.new('role::a')
      b = PuppetlabsOnceover::Class.new('profile::b')
      expect(PuppetlabsOnceover::Class.find('/role::/')).to eq([a])
      expect(PuppetlabsOnceover::Class.find('/role::/')).not_to include(b)
    end
  end

  describe ".all" do
    it "returns every class created so far" do
      a = PuppetlabsOnceover::Class.new('role::a')
      b = PuppetlabsOnceover::Class.new('role::b')
      expect(PuppetlabsOnceover::Class.all).to eq([a, b])
    end
  end
end
