require 'curb'
require 'json'
require 'inifile'

module DynFirewall
  class Node

    def initialize
      @config = DynFirewall::Config.instance
    end

    # -------------------------------------------------------------------------
    def run
      # Performance: require here so that launching other stuff doesn't load the library
      require 'eventmachine'

      EM.run do
        repeat_action('/usr/local/bin/dynfw_node keepalive',   @config.conf['node']['keepalive_delay'].to_i,0)
        repeat_action('/usr/local/bin/dynfw_node check_rules',@config.conf['node']['check_rules_delay'].to_i,10)
        EM.add_timer(@config.conf['node']['max_run_duration'].to_i) do
          puts "has run long enough"
          EM.stop
        end
      end
    end

    def repeat_action(cmd,delay,splay=0)
      EM.system(cmd,proc do |output,status|
        puts "CMD END: #{cmd} #{status} #{output.strip}"
        EM.add_timer(((status.success?) ? delay+rand(splay+1) : 5),proc{repeat_action(cmd,delay,splay)})
      end
      )
    end

    # -------------------------------------------------------------------------
    def keepalive
      hostname,env = @config.conf['node'].values_at('hostname','env')
      c = Curl::Easy.new(@config.conf['global']['endpoint'] + '/quick_and_dirty_server_add/' + hostname + '/' + env)
      c.http_auth_types = :basic
      c.username = @config.conf['api']['http_user']
      c.password = @config.conf['api']['http_password']
      c.put((@config.conf['node']['keepalive_delay'].to_i * 2).to_s)
    end

    def check_rules
      c = Curl::Easy.new()
      c.http_auth_types = :basic
      c.username = @config.conf['api']['http_user']
      c.password = @config.conf['api']['http_password']

      c.url = @config.conf['global']['endpoint'] + '/rules/' + @config.conf['node']['env']
      c.perform

      build_conf = [ "## START DYNFW RULES ##"]

      rules_raw = JSON.parse(c.body_str)
      rules_raw.sort{|a,b| a['tag'] <=> b['tag'] }.each do |rule_line|
        tag,rules,comment = rule_line.values_at('tag','rules','comment')
        comment = "" if comment.nil?
        build_conf << ("# TAG: #{tag}, COMMENT: " + comment.gsub(/\r\n/,' '))
        rules.gsub(/\r/,"\n").split("\n").each do |rule|
          next if rule == ''
          build_conf << rule
        end
      end

      build_conf << "## END DYNFW RULES ##"

      # build newdata
      newdata = File.read("/etc/iptables.rules")
      already_in = {}
      newdata.split("\n").each do |line|
        already_in[line] = true
      end
      build_conf = build_conf.collect {|line| (already_in.has_key? line) ? "#IGNORED AS DUPLICATE #{line}" : line }
      newdata = newdata.sub("## DYNFW REPLACE ##",build_conf.join("\n"))

      if (!(File.exists? "/var/run/dynfw/iptables.rules")) or 
      newdata.split("\n").delete_if {|x| x =~ /^#/ }.join("\n") != File.read("/var/run/dynfw/iptables.rules").split("\n").delete_if {|x| x =~ /^#/ }.join("\n")

        File.write("/var/run/dynfw/iptables.rules.new",newdata)
        puts "apply new rules"
        system "cat /var/run/dynfw/iptables.rules.new | sudo /sbin/iptables-restore"
        raise "unable to execute: #{$?}" unless $?.success?
        File.rename "/var/run/dynfw/iptables.rules.new","/var/run/dynfw/iptables.rules"
      end

    end
  end
end
