# mruby-redis-cluster   [![Build Status](https://travis-ci.org/yukirii/mruby-redis-cluster.svg?branch=master)](https://travis-ci.org/yukirii/mruby-redis-cluster)

mruby-redis-cluster is a mruby client library for [Redis Cluster](https://redis.io/topics/cluster-spec) based on [matsumotory/mruby-redis](https://github.com/matsumotory/mruby-redis/).

## INSTALLATION

#### Using mrbgems

Add conf.gem line to `build_config.rb`:

```ruby
MRuby::Build.new do |conf|

  # ... (snip) ...

  conf.gem :github => 'yukirii/mruby-redis-cluster'
end
```

## USAGE

### Connecting to a Redis Cluster

```ruby
startup_nodes = [
  { host: '127.0.0.1', port: 7000 },
  { host: '127.0.0.1', port: 7001 }
]
rc = RedisCluster.new(startup_nodes)
```

### Commands

#### `Redis#expire` [doc](http://redis.io/commands/expire)

```ruby
client.expire key, 10
```

#### `Redis#get` [doc](http://redis.io/commands/get)

```ruby
client.get "key"
```

#### `Redis#set` [doc](http://redis.io/commands/set)

```ruby
client.set key, "200"
```

## License

[MIT](https://github.com/yukirii/mruby-redis-cluster/blob/master/LICENSE)

## Authors

The RedisCluster client and RedisClusterCRC16 module in mruby-redis-cluster based on [antirez/redis-rb-cluster](https://github.com/antirez/redis-rb-cluster).
