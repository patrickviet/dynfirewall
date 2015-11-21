require 'dynfirewall/config'
require 'dynfirewall/cli'
require 'dynfirewall/node'
require 'dynfirewall/apiclient'

module DynFirewall
  def DynFirewall.where_is(f)
    File.expand_path "../#{f}", __FILE__
  end
end

