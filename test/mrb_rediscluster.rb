##
## RedisCluster Test
##

HOSTS = [
  { host: '127.0.0.1', port: 7000 },
  { host: '127.0.0.1', port: 7001 },
]

assert('Redis#ping') do
  r = RedisCluster.new(HOSTS)

  assert_equal 'PONG', r.ping
  r.close

  assert_raise(Redis::ClosedError) { r.ping }
end

assert('Redis#set, Redis#get') do
  r = RedisCluster.new(HOSTS)

  result = r.set 'hoge', 'fuga'
  ret = r.get 'hoge'
  r.close

  assert_equal 'OK', result
  assert_equal 'fuga', ret
  assert_raise(Redis::ClosedError) { r.get 'hoge' }
  assert_raise(Redis::ClosedError) { r.set 'hoge', 'fuga' }
end
