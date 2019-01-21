##
## RedisCluster Test
##

HOSTS = [
  { host: '127.0.0.1', port: 7000 },
  { host: '127.0.0.1', port: 7001 },
]

assert('RedisCluster#extract_key') do
  rc = RedisCluster.new(HOSTS)
  %i(info multi exec slaveof config shutdown).each do |cmd|
    assert_equal nil, rc.extract_key([cmd])
  end
  assert_equal 'key', rc.extract_key([:set, 'key', 'value'])
  assert_equal 'key', rc.extract_key([:get, 'key'])
end

assert('RedisCluster#set, RedisCluster#get') do
  rc = RedisCluster.new(HOSTS)

  result = rc.set 'hoge', 'fuga'
  ret = rc.get 'hoge'
  assert_equal 'OK', result
  assert_equal 'fuga', ret
end
