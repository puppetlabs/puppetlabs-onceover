require 'cri'
require 'puppetlabs-onceover/controlrepo'
require 'puppetlabs-onceover/cli'
require 'puppetlabs-onceover/logger'

class PuppetlabsOnceover
  class CLI
    class Update
      def self.command
        @command ||= Cri::Command.define do
          name 'update'
          usage 'update puppetfile'
          summary 'Updates stuff, currently only the Puppetfile'

          run do |opts, args, cmd|
            # Print out the description
            puts cmd.help(:verbose => opts[:verbose])
            exit 0
          end
        end
      end

      class Puppetfile
        def self.command
          @command ||= Cri::Command.define do
            name 'puppetfile'
            usage 'puppetfile'
            summary 'Update all modules in the Puppetfile'
            description <<-DESCRIPTION
Updates all modules to their latest version and writes that
file back onto the system over the original Puppetfile.
            DESCRIPTION

            run do |opts, args, cmd|
              # Print out the description
              PuppetlabsOnceover::Controlrepo.new(opts).update_puppetfile
              exit 0
            end
          end
        end
      end
    end
  end
end

# Register itself
PuppetlabsOnceover::CLI.command.add_command(PuppetlabsOnceover::CLI::Update.command)
PuppetlabsOnceover::CLI::Update.command.add_command(PuppetlabsOnceover::CLI::Update::Puppetfile.command)
