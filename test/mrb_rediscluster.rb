##
## RedisCluster Test
##

assert("RedisCluster#hello") do
  t = RedisCluster.new "hello"
  assert_equal("hello", t.hello)
end

assert("RedisCluster#bye") do
  t = RedisCluster.new "hello"
  assert_equal("hello bye", t.bye)
end

assert("RedisCluster.hi") do
  assert_equal("hi!!", RedisCluster.hi)
end
