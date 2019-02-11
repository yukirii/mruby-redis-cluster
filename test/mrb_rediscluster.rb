##
## RedisCluster Test
##

HOSTS = [
  { host: '127.0.0.1', port: 7000 },
  { host: '127.0.0.1', port: 7001 },
]

class MockRedis < Mocks::Mock
  attr_reader :host, :port

  def initialize(host, port)
    super()
    @host = host
    @port = port
    self.stubs(:ping).returns('PONG')
  end

  def cluster(cmd)
    if cmd == 'slots'
      [
        [0, 5460, ["127.0.0.1", 7000, "0000"], ["127.0.0.1", 7003, "3333"]],
        [5461, 10922, ["127.0.0.1", 7001, "1111"], ["127.0.0.1", 7004, "4444"]],
        [10923, 16383, ["127.0.0.1", 7002, "2222"], ["127.0.0.1", 7005, "5555"]]
      ]
    elsif cmd == 'nodes'
      "0000 127.0.0.1:7000@17000 myself,master - 0 1549881077000 1 connected 0-5460\n" +
      "1111 127.0.0.1:7001@17001 master - 0 1549881079505 2 connected 5461-10922\n" +
      "2222 127.0.0.1:7002@17002 master - 0 1549881079000 3 connected 10923-16383\n" +
      "3333 127.0.0.1:7003@17003 slave 0000 0 1549881079102 4 connected\n" +
      "4444 127.0.0.1:7004@17004 slave 1111 0 1549881079505 5 connected\n" +
      "5555 127.0.0.1:7005@17005 slave 2222 0 1549881079505 6 connected\n"
    end
  end
end

assert('RedisCluster#get_cluster_nodes') do
  rc = RedisCluster.new(HOSTS)
  rc.define_singleton_method(:get_redis_link) { |node| MockRedis.new(node[:host], node[:port]) }

  expect = {
    '0000' => { host: '127.0.0.1', port: 7000, name: '127.0.0.1:7000@17000', flags: ['master'] },
    '1111' => { host: '127.0.0.1', port: 7001, name: '127.0.0.1:7001@17001', flags: ['master'] },
    '2222' => { host: '127.0.0.1', port: 7002, name: '127.0.0.1:7002@17002', flags: ['master'] },
    '3333' => { host: '127.0.0.1', port: 7003, name: '127.0.0.1:7003@17003', flags: ['slave'] },
    '4444' => { host: '127.0.0.1', port: 7004, name: '127.0.0.1:7004@17004', flags: ['slave'] },
    '5555' => { host: '127.0.0.1', port: 7005, name: '127.0.0.1:7005@17005', flags: ['slave'] }
  }

  assert_equal expect, rc.get_cluster_nodes(HOSTS)
end

assert('RedisCluster#cluster_nodes') do
  rc = RedisCluster.new(HOSTS)
  rc.define_singleton_method(:get_redis_link) { |node| MockRedis.new(node[:host], node[:port]) }
  rc.initialize_slots_cache

  assert_equal '0000', rc.instance_variable_get('@slots')[0]
  assert_equal '0000', rc.instance_variable_get('@slots')[5460]
  assert_equal '1111', rc.instance_variable_get('@slots')[5461]
  assert_equal '1111', rc.instance_variable_get('@slots')[10922]
  assert_equal '2222', rc.instance_variable_get('@slots')[10923]
  assert_equal '2222', rc.instance_variable_get('@slots')[16383]
end

assert('RedisCluster#get_connection_by') do
  rc = RedisCluster.new(HOSTS)
  rc.define_singleton_method(:get_redis_link) { |node| MockRedis.new(node[:host], node[:port]) }
  rc.define_singleton_method(:get_random_connection) { MockRedis.new('192.0.2.1', 6379) }
  rc.initialize_slots_cache

  conn = rc.get_connection_by(16383)
  assert_equal '127.0.0.1', conn.host
  assert_equal 7002, conn.port

  # clear slot cache, expect get_random_connection() is called
  rc.instance_variable_get('@slots')[16383] = nil

  conn = rc.get_connection_by(16383)
  assert_equal '192.0.2.1', conn.host
  assert_equal 6379, conn.port
end

assert('RedisCluster#get_random_connection') do
  rc = RedisCluster.new(HOSTS)
  rc.define_singleton_method(:get_redis_link) { |node| MockRedis.new(node[:host], node[:port]) }
  rc.initialize_slots_cache

  nodes = {
    '1234' => { host: '192.0.2.1', port: 7000, name: '192.0.2.1:7000', flags: ['master'] }
  }
  rc.instance_variable_set('@nodes', nodes)
  rc.instance_variable_get('@connections')['1234'] = nil

  conn = rc.get_random_connection
  assert_equal '192.0.2.1', conn.host
  assert_equal 7000, conn.port
  assert_equal conn, rc.instance_variable_get('@connections')['1234']

  rc.instance_variable_get('@connections')['1234'].stubs(:ping).returns(nil)
  assert_raise(RuntimeError) { rc.get_random_connection }

  rc.instance_variable_set('@nodes', {})
  assert_raise(RuntimeError) { rc.get_random_connection }
end

assert('RedisCluster#send_cluster_command') do
  rc = RedisCluster.new(HOSTS)
  rc.define_singleton_method(:get_redis_link) do |node|
    mock = MockRedis.new(node[:host], node[:port])
    mock.define_singleton_method(:send) do
      return '123456789' if self.port == 7002
      raise Redis::ReplyError, 'MOVED 12739 127.0.0.1:7002'
    end
    mock
  end
  rc.initialize_slots_cache

  assert_equal '123456789', rc.send_cluster_command([:get, '123456789'])

  # set wrong node id
  rc.instance_variable_get('@slots')[12739] = '0000'
  assert_equal '123456789', rc.send_cluster_command([:get, '123456789'])
end

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
  assert_equal 'OK', rc.set('hoge', 'fuga')
  assert_equal 'fuga', rc.get('hoge')
end

assert('RedisCluster#hash_slot') do
  rc = RedisCluster.new(HOSTS)
  assert_equal rc.hash_slot('{user1000}.following'), rc.hash_slot('{user1000}.followers')
  assert_equal rc.hash_slot('foo{{bar}}zap'), rc.hash_slot('{bar')
  assert_equal rc.hash_slot('foo{bar}{zap}'), rc.hash_slot('bar')
end

assert('RedisCluster#close_connection') do
  assert_raise(TypeError) { RedisCluster.new(HOSTS).close_connection("test") }
end
