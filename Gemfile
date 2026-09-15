# For puppetcore, set GEM_SOURCE_PUPPETCORE = 'https://rubygems-puppetcore.puppet.com'
gemsource_default = ENV['GEM_SOURCE'] || 'https://rubygems.org'
gemsource_puppetcore = if ENV['GEM_SOURCE']
                         gemsource_default
                       elsif ENV['PUPPET_FORGE_TOKEN'] && !ENV['PUPPET_FORGE_TOKEN'].empty?
                         'https://rubygems-puppetcore.puppet.com'
                       else
                         ENV['GEM_SOURCE_PUPPETCORE'] || gemsource_default
                       end
source gemsource_default

gemspec

gem 'pry-coolline', '> 0.0', '< 1.0.0'

# Route through gemsource_puppetcore so CI can resolve puppet ~> 9.0 from the
# private Puppetcore registry (public rubygems.org tops out at puppet 8.10.0).
# When PUPPET_FORGE_TOKEN is unset (e.g. fork PRs, local dev without a token),
# gemsource_puppetcore falls through to gemsource_default (public rubygems.org)
# and no auth is attempted against Puppetcore.
gem 'puppet', ENV['PUPPET_GEM_VERSION'] || '~> 8', source: gemsource_puppetcore

# facter is a runtime dependency of puppet, but pinning `puppet`'s own source
# does NOT pin its transitive dependencies to that same source -- bundler
# still resolves facter from whichever source(s) declare it, so without this
# explicit pin facter would silently keep resolving from public rubygems.org
# (built from the public facter repo) even when puppet itself correctly comes
# from Puppetcore (built from the private facter-private source). Pin it
# explicitly so both come from the same place.
gem 'facter', source: gemsource_puppetcore

# Puppet on Ruby 3.3 / 3.4 has some missing dependencies
gem 'syslog', '~> 0.3' if RUBY_VERSION >= '3.4'

# json 3.0 made JSON.parse keyword-only (dropped the legacy positional-hash
# opts argument). faraday's JSON response middleware
# (Faraday::Response::Json#parse) still calls `decoder.public_send(method,
# body, @parser_options || {})` positionally, so with json ~> 3.0 every
# Forge/HTTP JSON response r10k parses raises
# `wrong number of arguments (given 2, expected 1)`. Pin to the last
# compatible major until faraday releases a fix for json 3.0's new
# signature.
gem 'json', '< 3.0'

# Windows platform runtime deps. The published puppet/openvox rubygems.org
# artefacts are built on Linux and guard `ffi` / `win32ole` with build-host
# platform checks, so those deps never make it into the Linux-published
# artefact. Ruby 3.4+ removed win32ole from default gems, making the missing
# declaration fatal at require-time on Windows. Declaring them here in the
# Gemfile is evaluated on the install host at bundle time, so bundler pulls
# them on Windows only.
platforms :mingw, :x64_mingw, :mswin do
  gem 'ffi', '>= 1.15.5', '< 1.17.0', '!= 1.16.0', '!= 1.16.1', '!= 1.16.2'
  gem 'win32ole', '>= 1.8', '< 2.0'
end

group :test do
  # Required for the final controlrepo tests
  gem 'rexml', '~> 3.3', '>= 3.3.9'
  gem 'simplecov', require: false
  gem 'toml-rb'
end

group :development do
  gem 'cucumber'
  gem 'pry'
  gem 'puppetlabs-syntax'
  gem 'rubocop'
  gem 'rubygems-tasks'
end

# Evaluate Gemfile.local if it exists
if File.exist? "#{__FILE__}.local"
  eval(File.read("#{__FILE__}.local"), binding)
end

# Evaluate ~/.gemfile if it exists
if File.exist?(File.join(Dir.home, '.gemfile'))
  eval(File.read(File.join(Dir.home, '.gemfile')), binding)
end

group :release, optional: true do
  gem 'faraday-retry', '~> 2.1', require: false
  gem 'github_changelog_generator', '~> 1.18', require: false
end
