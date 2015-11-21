require 'sinatra/base'
require 'json'
require 'dynfirewall/config'
require 'cassandra'
require 'bcrypt'

module DynFirewall
  class API < Sinatra::Base

    def initialize
      super

      reconnect_interval = 2

      @config = DynFirewall::Config.instance
      @cassandra_cluster = Cassandra.cluster(
        reconnection_policy: Cassandra::Reconnection::Policies::Constant.new(reconnect_interval),
      )
      @cass = @cassandra_cluster.connect(@config.conf['api']['keyspace'])
    end

    # -----------------------------------------------------------------------------
    # Some Auth stuff
    def protected!
      return if authorized?
      headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
      halt 401, "Not authorized\n"
    end

    def authorized?
      @auth ||=  Rack::Auth::Basic::Request.new(request.env)
      @auth.provided? and @auth.basic? and @auth.credentials and @auth.credentials == @config.conf['api'].values_at('http_user','http_password')
    end

    get '/health' do
      "OK"
    end

    get '/ping' do
      "OK"
    end

    # -----------------------------------------------------------------------------
    get '/rules/:env' do |env|
      if @env['REMOTE_ADDR'] != '127.0.0.1' or (@env.has_key?'HTTP_X_FORWARDED_FOR' and @env['HTTP_X_FORWARDED_FOR'] != '127.0.0.1')
        protected!
      end

      ret = []

      statement = @cass.prepare("SELECT tag,rules,comment FROM fwentry WHERE env = ?")
      @cass.execute(statement, arguments: [env]).each do |row|
        ret << row
      end

      ret.to_json
    end


    put '/quick_and_dirty_server_add/:hostname/:srvenv' do |hostname,srvenv|
      protected! if @env['REMOTE_ADDR'] != '127.0.0.1' or (@env.has_key?'HTTP_X_FORWARDED_FOR' and @env['HTTP_X_FORWARDED_FOR'] != '127.0.0.1')
      #params = JSON.parse(request.body.read)

      addr = (@env.has_key?'HTTP_X_FORWARDED_FOR') ? @env['HTTP_X_FORWARDED_FOR'] : @env['REMOTE_ADDR'] 

      # Just a quick and dirty server add
      @cass.execute("INSERT INTO fwentry (tag,env,rules,comment) VALUES('dirty_add_#{hostname}_#{srvenv}','#{srvenv}','-A INPUT -s #{addr} -j ACCEPT','#{Time.new}') USING TTL 3600")

      "OK"
    end

    put '/tmp_client_add/:ip/:clientenv' do |ip,clientenv|
      protected! if @env['REMOTE_ADDR'] != '127.0.0.1' or (@env.has_key?'HTTP_X_FORWARDED_FOR' and @env['HTTP_X_FORWARDED_FOR'] != '127.0.0.1')

      halt 500, "Incorrect IP format" unless ip =~ /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$/
      halt 500, "incorrect IP format" unless (ip.split('.').keep_if{|n| n.to_i >= 0 and n.to_i <= 255 }).count == 4

      @cass.execute("INSERT INTO fwentry (tag,env,rules,comment) VALUES('tmp_client_add_#{ip}_#{clientenv}','#{clientenv}','-A INPUT -s #{ip} -j ACCEPT','#{Time.new}') USING TTL 86400")

      "OK"
    end

    get '/' do
      addr = (@env.has_key?'HTTP_X_FORWARDED_FOR') ? @env['HTTP_X_FORWARDED_FOR'] : @env['REMOTE_ADDR']
      erb :index_form, :locals => {:addr => addr}
    end

    post '/' do
      addr = (@env.has_key?'HTTP_X_FORWARDED_FOR') ? @env['HTTP_X_FORWARDED_FOR'] : @env['REMOTE_ADDR']
      username,password = params.values_at(:username, :password)

      # passwords are in bcrypt format.
      q = @cass.execute(@cass.prepare("select password,rules,ttl FROM users WHERE username = ?"), arguments: [username])
      if q.count > 0
        r = q.first
        if BCrypt::Password.new(r['password']) == password
          ttl = r['ttl'] || 86400
          clientenv = 'production' #FIXME: add multi env support
          @cass.execute("INSERT INTO fwentry (tag,env,rules,comment,username) VALUES('webadd_#{addr}','#{clientenv}','-A INPUT -s #{addr} -j ACCEPT','#{Time.new} TTL #{ttl}','#{username}') USING TTL #{ttl}")
          "Added IP #{addr} for #{ttl} secs"  
        else
          halt 403, "username error"
        end
      else
        halt 403, "username error"
      end
    end
  end
end
