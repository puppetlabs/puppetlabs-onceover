require 'cri'
require 'puppetlabs-onceover/controlrepo'
require 'puppetlabs-onceover/cli'
require 'puppetlabs-onceover/logger'

class PuppetlabsOnceover
  class CLI
    class Show
      def self.command
        @command ||= Cri::Command.define do
          name 'show'
          usage 'show [controlrepo|puppetfile]'
          summary 'Shows the current state of things'
          description <<-DESCRIPTION
Shows the state of either the controlrepo or the Puppetfile
          DESCRIPTION

          run do |opts, args, cmd|
            # Print out the description
            puts cmd.help(:verbose => opts[:verbose])
            exit 0
          end
        end
      end

      class Repo
        def self.command
          @command ||= Cri::Command.define do
            name 'repo'
            usage 'repo [options]'
            summary 'Shows the current state of the Controlrepo'
            description <<-DESCRIPTION
Shows the state of the repo as the tool sees it.
Useful for debugging.
            DESCRIPTION

            run do |opts, args, cmd|
              repo   = PuppetlabsOnceover::Controlrepo.new(opts)
              config = PuppetlabsOnceover::TestConfig.new(repo.onceover_yaml, opts)
              # Print out the description
              puts "--- Controlrepo Information ---"
              puts repo.to_s
              puts "\n--- Test Configuration ---"
              puts config.to_s
              exit 0
            end
          end
        end
      end

      class Puppetfile
        def self.command
          @command ||= Cri::Command.define do
            name 'puppetfile'
            usage 'puppetfile [options]'
            summary 'Shows the current state of the puppetfile'
            description <<-DESCRIPTION
Shows the state of the puppetfile including current versions and
latest versions of each module. Great for checking for updates.
To update all modules run `onceover update puppetfile`. (Hint: once
you have done the update, run the tests to make sure nothing breaks.)
            DESCRIPTION

            run do |opts, args, cmd|
              # Print out the description
              PuppetlabsOnceover::Controlrepo.new(opts).print_puppetfile_table
              exit 0
            end
          end
        end
      end
    end
  end
end

# Register itself
PuppetlabsOnceover::CLI.command.add_command(PuppetlabsOnceover::CLI::Show.command)
PuppetlabsOnceover::CLI::Show.command.add_command(PuppetlabsOnceover::CLI::Show::Repo.command)
PuppetlabsOnceover::CLI::Show.command.add_command(PuppetlabsOnceover::CLI::Show::Puppetfile.command)
