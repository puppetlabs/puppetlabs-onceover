require 'spec_helper'
require 'puppetlabs-onceover/controlrepo'

describe "PuppetlabsOnceover::Controlrepo" do
  context "in a barebones controlrepo" do
    before do
      @repo = PuppetlabsOnceover::Controlrepo.new(
        {
          path: 'spec/fixtures/controlrepos/minimal'
        }
      )
    end

    context "without hiera.yaml" do
      it { expect(@repo.hiera_config_file_relative_path).to be_nil }
    end
  end
end
