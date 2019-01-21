class RedisCluster

  DEFAULT_MAX_CACHED_CONNECTIONS = 2
  HASH_SLOTS = 16384

  attr_accessor :slots
  attr_accessor :nodes
  attr_accessor :startup_nodes

  def initialize(startup_nodes, max_cached_connections=nil)
    @startup_nodes = startup_nodes
    @max_cached_connections = max_cached_connections || DEFAULT_MAX_CACHED_CONNECTIONS

    @slots = {}
    @nodes = []
    @connections = {}

    initialize_slots_cache
  end

  def ping
    raise NotImplementedError
  end

  def method_missing(*argv)
    send_cluster_command(argv)
  end

  def initialize_slots_cache
    @startup_nodes.map { |n| n[:name] = "#{n[:host]}:#{n[:port]}" }

    # TODO: implement retry process
    n = @startup_nodes[0]
    redis = Redis.new(n[:host], n[:port], 2)
    slots = redis.cluster("slots")

    slots.each do |r|
      (r[0]..r[1]).each do |slot|
        host, port = r[2]
        node = {
          host: host,
          port: port,
          name: "#{host}:#{port}"
        }
        @nodes << node
        @slots[slot] = node

        unless @startup_nodes.include?(node)
          @startup_nodes << node
        end
      end
    end
  end

  def send_cluster_command(argv)
    key = extract_key(argv)
    slot = hash_slot(key)

    redis = get_connection_by(slot)
    return redis.send(argv[0], *argv[1..-1])
  end

  def get_connection_by(slot)
    node = @slots[slot]

    if ! @connections[node[:name]]
      close_existing_connection
      @connections[node[:name]] = Redis.new(node[:host], node[:port], 2)
    end

    @connections[node[:name]]
  end

  def close_existing_connection
    while @connections.length >= DEFAULT_MAX_CACHED_CONNECTIONS
      @connections.each do |n, c|
        c.close
        @connections.delete(n)
      end
    end
  end

  def extract_key(argv)
    cmd = argv[0].to_s.downcase
    if %w(info multi exec slaveof config shutdown).include?(cmd)
      return nil
    end
    return argv[1]
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
