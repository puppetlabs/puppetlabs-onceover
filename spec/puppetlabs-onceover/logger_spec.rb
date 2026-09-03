require 'spec_helper'
require 'puppetlabs-onceover/logger'

describe PuppetlabsOnceover::Logger do
  let(:includer) do
    Class.new do
      include PuppetlabsOnceover::Logger
    end.new
  end

  before(:each) do
    $logger = nil
  end

  after(:each) do
    $logger = nil
  end

  it 'lazily builds a Logging logger with a stdout appender on first call' do
    logger = includer.logger
    expect(logger).to eq(Logging.logger['Colors'])
    expect(Logging::LNAMES[logger.level]).to eq('INFO')
  end

  it 'memoizes the logger across calls' do
    first = includer.logger
    second = includer.logger
    expect(first).to equal(second)
  end
end
