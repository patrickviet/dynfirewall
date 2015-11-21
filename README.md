# dynfirewall
Dynamic Firewall

TODO: document better. Publish the chef recipe. Could also easily work w/ puppet.
Nobody does this manually, that would be retarded.

General structure: you run the API, accessible via https, potentially load balanced/highly available (hopefully...). It runs cassandra on the same nodes as the API, and the API accesses the local cassandra.

Each node runs dynfw_node, which will register itself, and fetch the rules.




Modules:
- API (Sinatra based - requires Cassandra and NGINX or other proxy)
- Node/Daemon (runs on every server)
- CLI

Build gem:
```gem build dynfirewall.gemspec```

Install gem:
```gem install dynfirewall-x.y.z.gem```

Setup IPTables
--------------

Have a /etc/iptables.rules file that contains at some point 
```## DYNFW REPLACE ##```

Full example

```
# File: /etc/iptables.rules
### Non stateful example
### Super high performance - slightly lower security
# Firewall configuration created and managed by chef
# Do not edit manually
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
# NON SYN FOR ESTABLISHED + DNS
-A INPUT -p tcp ! --syn -j ACCEPT
-A INPUT -p udp --sport 53 -j ACCEPT

# PING REQ AND REPLY
-A INPUT -p icmp --icmp-type 8 -j ACCEPT
-A INPUT -p icmp --icmp-type 0 -j ACCEPT

# TRACEROUTE
-A INPUT -p icmp --icmp-type 3 -j ACCEPT
-A INPUT -p icmp --icmp-type 11 -j ACCEPT

-A INPUT -i lo -j ACCEPT

# This will be replaced by dynfw extra rules
## DYNFW REPLACE ##

-A INPUT -j DROP
COMMIT
```


Run Cassandra
-------------
Standard Cassandra setup on the same host as API server(s)

Here is from the test env.

```
cqlsh:dynfirewall> describe dynfirewall

CREATE KEYSPACE dynfirewall WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '3'}  AND durable_writes = true;

CREATE TABLE dynfirewall.fwentry (
    tag text PRIMARY KEY,
    comment text,
    create_stamp int,
    env text,
    expiry_stamp int,
    rules text,
    username text
) WITH bloom_filter_fp_chance = 0.01
    AND caching = '{"keys":"ALL", "rows_per_partition":"NONE"}'
    AND comment = ''
    AND compaction = {'min_threshold': '4', 'class': 'org.apache.cassandra.db.compaction.SizeTieredCompactionStrategy', 'max_threshold': '32'}
    AND compression = {'sstable_compression': 'org.apache.cassandra.io.compress.LZ4Compressor'}
    AND dclocal_read_repair_chance = 0.1
    AND default_time_to_live = 0
    AND gc_grace_seconds = 864000
    AND max_index_interval = 2048
    AND memtable_flush_period_in_ms = 0
    AND min_index_interval = 128
    AND read_repair_chance = 0.0
    AND speculative_retry = '99.0PERCENTILE';
CREATE INDEX env ON dynfirewall.fwentry (env);

CREATE TABLE dynfirewall.users (
    username text PRIMARY KEY,
    active int,
    envlist text,
    password text,
    rules text,
    ttl int
) WITH bloom_filter_fp_chance = 0.01
    AND caching = '{"keys":"ALL", "rows_per_partition":"NONE"}'
    AND comment = ''
    AND compaction = {'min_threshold': '4', 'class': 'org.apache.cassandra.db.compaction.SizeTieredCompactionStrategy', 'max_threshold': '32'}
    AND compression = {'sstable_compression': 'org.apache.cassandra.io.compress.LZ4Compressor'}
    AND dclocal_read_repair_chance = 0.1
    AND default_time_to_live = 0
    AND gc_grace_seconds = 864000
    AND max_index_interval = 2048
    AND memtable_flush_period_in_ms = 0
    AND min_index_interval = 128
    AND read_repair_chance = 0.0
    AND speculative_retry = '99.0PERCENTILE';
```

Run API
-------

```
# /etc/dynfirewall.ini
[global]
endpoint = https://dynfirewall.xyz.net
[node]
hostname = myhostname #(in chef erb: node.hostname)
ipaddr = 1.2.3.4 #(in chef erb: node.ipaddress)
keepalive_delay = 60
check_rules_delay = 10
env = production
max_run_duration = 86400
[api]
http_user = dynfw
http_password = somesecretpassword
keyspace = dynfirewall
```

Don't forget to create a dynfw user (or other) to run the API.

Runit file: /etc/service/runit/dynfw_api/run
```
#!/bin/sh
exec chpst -u dynfw rackup -s thin -o 0.0.0.0 -p 12345 $(dynfw_filepath config.ru)
```

NGINX Config. You'll need a real valid SSL cert. And have this publically accessible (or at least to the IPs you'd like to be able to authorize themselves...)
```
server {
  listen 443 ssl;
  server_name dynfirewall.xyz.net;
  ssl_certificate /etc/ssl/certs/xyz.net.crt;
  ssl_certificate_key /etc/ssl/private/xyz.net.key;

  location / {
    proxy_pass http://localhost:12345;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header Host $host;
  }
}
```

Node/Daemon
-----------

It runs as root... 'cause we're manipulating IPtables here, right?

File: /etc/service/dynfw_node/run
```
#!/bin/sh

exec dynfw_node
```

CLI
---

For now just a command as root:
```# dynfw addip```

adds your ip (from ssh env)

