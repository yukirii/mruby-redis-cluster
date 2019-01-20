class RedisCluster

  DEFAULT_MAX_CACHED_CONNECTIONS = 2

  def initialize(initial_nodes, max_cached_connections=nil)
    @initial_nodes = initial_nodes
    @max_cached_connections = max_cached_connections || DEFAULT_MAX_CACHED_CONNECTIONS

    @slots = {}
    @nodes = []

    initialize_slots_cache
  end

  def ping
    raise NotImplementedError
  end

  def get(key)
    raise NotImplementedError
  end

  def get(key)
    raise NotImplementedError
  end

  def set(key, value)
    raise NotImplementedError
  end

  def initialize_slots_cache
    @initial_nodes.each do |n|
      redis = Redis.new(n[:host], n[:port], 2)
      redis.cluster("slots")
    end
  end

  def hash_slot(key)
    s = key.index "{"
    if s
      e = key.index "}",s+1
      if e && e != s+1
        key = key[s+1..e-1]
      end
    end
    RedisClusterCRC16.crc16(key) % HASH_SLOTS
  end
end
