require 'spec_helper'
require 'puppetlabs-onceover/version'

describe PuppetlabsOnceover do
  it 'defines a VERSION constant' do
    # Not a literal version string -- release-prep bumps this file on every
    # release, which would otherwise break this test every single time.
    expect(PuppetlabsOnceover::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
