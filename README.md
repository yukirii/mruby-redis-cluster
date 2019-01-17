# mruby-redis-cluster   [![Build Status](https://travis-ci.org/shiftky/mruby-redis-cluster.svg?branch=master)](https://travis-ci.org/shiftky/mruby-redis-cluster)
RedisCluster class
## install by mrbgems
- add conf.gem line to `build_config.rb`

```ruby
MRuby::Build.new do |conf|

    # ... (snip) ...

    conf.gem :github => 'shiftky/mruby-redis-cluster'
end
```
## example
```ruby
p RedisCluster.hi
#=> "hi!!"
t = RedisCluster.new "hello"
p t.hello
#=> "hello"
p t.bye
#=> "hello bye"
```

## License
under the MIT License:
- see LICENSE file
