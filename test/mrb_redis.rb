##
## Redis Test
##

HOST = '127.0.0.1'
PORT = 7000
TIMEOUT = 2

# TODO:
# assert('Redis#cluster') do
# end

assert('Redis#asking') do
  r = Redis.new(HOST, PORT, TIMEOUT)
  assert_equal 'OK', r.asking
end
