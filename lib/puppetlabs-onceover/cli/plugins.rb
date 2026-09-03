require 'rubygems'

# Get all of the gems that start with puppetlabs-onceover-
plugins = Gem::Specification.group_by{ |g| g.name }.keep_if do |name, details|
  name =~ /^puppetlabs-onceover-.*$/
end.keys

plugins.each do |plugin|
  require plugin.sub('puppetlabs-onceover-', 'puppetlabs-onceover/')
end
