require 'dynfirewall/apiclient'
require 'json'
require 'inifile'

module DynFirewall
  class CLI

    def initialize
      @config = DynFirewall::Config.instance
      @client = DynFirewall::APIClient.instance
      @env = @config.conf['cli']['default_env']
    end

    def run!
      #begin
        cmds = []
        ARGV.each do |arg|
          cmd = arg.split(':',2)
          unless respond_to?(cmd[0])
            raise "no such command '#{cmd[0]}' in #{self.class} (#{__FILE__})"
          end
          cmds << cmd
        end

        cmds.each do |cmd|
          m = method(cmd[0]).parameters

          # only zero or one param
          raise "method #{cmd[0]} takes several parameters. This is a progamming mistake. Ask Patrick to edit #{__FILE__}" if m.length > 1

          if m.length == 1
            if cmd.length > 1
              # in this case it always works
              puts send(cmd[0],cmd[1])
            elsif m[0][0] == :opt
              puts send(cmd[0])
            else
              # This means you didn't give parameter to command that wants an option
              raise "method #{cmd[0]} requires an option. please specify with #{cmd[0]}:parameter"
            end
          else
            if cmd.length > 1
              raise "method #{cmd[0]} does not take parameters and you gave parameter #{cmd[1]}"
            else
              puts send(cmd[0])
            end
          end
        end
      #rescue Exception => e
      #  puts "ERROR: #{e}"
      #  exit 1
      #end
    end

    def mysystem(cmd)
      system cmd
      raise "error running #{cmd} #{$?}" unless $?.success?
    end

    def addip(ip=ENV['SSH_CLIENT'].split(' ').first)
      # FIXME: env is set by default to production?
      clientenv="production"

      raise "Incorrect IP format" unless ip =~ /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$/
      raise "incorrect IP format" unless (ip.split('.').keep_if{|n| n.to_i >= 0 and n.to_i <= 255 }).count == 4

      # now we are sure we have correct IP format. Let's insert this for 24hrs.
      @client.put("/tmp_client_add/#{ip}/#{clientenv}",'')
      return "Inserted ip #{ip} for 24hrs in #{clientenv}"

    end

    # -------------------------------------------------------------------------

  end
end

