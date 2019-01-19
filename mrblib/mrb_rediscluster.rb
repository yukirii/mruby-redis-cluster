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

end
