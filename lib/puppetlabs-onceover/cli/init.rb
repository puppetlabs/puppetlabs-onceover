require 'cri'
require 'puppetlabs-onceover/controlrepo'
require 'puppetlabs-onceover/cli'
require 'puppetlabs-onceover/runner'
require 'puppetlabs-onceover/testconfig'
require 'puppetlabs-onceover/logger'

class PuppetlabsOnceover
  class CLI
    class Init
      def self.command
        @command ||= Cri::Command.define do
          name 'init'
          usage 'init'
          summary 'Sets up a controlrepo for testing from scratch'
          description <<-DESCRIPTION
This will generate all of the config files required for the onceover
tool to work.
          DESCRIPTION

          run do |opts, args, cmd|
            PuppetlabsOnceover::Controlrepo.init(PuppetlabsOnceover::Controlrepo.new(opts))
            # Would it make sense for #init to be a class instance method of Controlrepo ? Then you could:
            # cp = PuppetlabsOnceover::Controlrepo.new(opts)
            # cp.init
          end
        end
      end
    end
  end
end

# Register itself
PuppetlabsOnceover::CLI.command.add_command(PuppetlabsOnceover::CLI::Init.command)
