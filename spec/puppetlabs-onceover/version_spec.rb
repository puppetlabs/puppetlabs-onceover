require 'spec_helper'
require 'puppetlabs-onceover/version'

describe PuppetlabsOnceover do
  it 'defines a VERSION constant' do
    expect(PuppetlabsOnceover::VERSION).to eq('5.0.3')
  end
end
