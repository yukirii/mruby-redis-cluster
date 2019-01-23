class RedisCluster

  HASH_SLOTS = 16384
  MAX_REDIRECTIONS = 16
  DEFAULT_MAX_CACHED_CONNECTIONS = 2

  def initialize(startup_nodes, max_cached_connections=nil)
    @startup_nodes = startup_nodes
    @max_cached_connections = max_cached_connections || DEFAULT_MAX_CACHED_CONNECTIONS

    @slots = {}
    @nodes = []
    @connections = {}
    @refresh_slots_cache = false

    initialize_slots_cache
  end

  def method_missing(*argv)
    send_cluster_command(argv)
  end

  def cluster_slots
    @startup_nodes.each do |n|
      begin
        redis = Redis.new(n[:host], n[:port])
        return redis.cluster('slots')
      rescue
        next
      end
    end
    raise 'Error: failed to get cluster slots'
  end

  def initialize_slots_cache
    @startup_nodes.map { |n| n[:name] = "#{n[:host]}:#{n[:port]}" }

    cluster_slots.each do |r|
      (r[0]..r[1]).each do |slot|
        host, port = r[2]
        node = { host: host, port: port, name: "#{host}:#{port}" }
        @nodes << node
        @slots[slot] = node

        unless @startup_nodes.include?(node)
          @startup_nodes << node
        end
      end
    end

    @refresh_slots_cache = false
  end

  def send_cluster_command(argv)
    initialize_slots_cache if @refresh_slots_cache

    try_random_connection = false
    asking = false
    num_redirects = 0

    key = extract_key(argv)
    slot = hash_slot(key)

    begin
      if try_random_connection
        redis = get_random_connection
        try_random_connection = false
      else
        redis = get_connection_by(slot)
      end

      redis.asking if asking
      asking = false

      return redis.send(argv[0], *argv[1..-1])
    rescue Redis::ConnectionError => e
      try_random_connection = true
      retry
    rescue Redis::ReplyError => e
      if num_redirects >= MAX_REDIRECTIONS
        raise "Error: #{argv[0]} #{argv[1..-1].join(' ')} - max redirection limit exceeded (#{MAX_REDIRECTIONS} times)"
      end

      err, newslot, ip_and_port = e.message.split
      if err == 'MOVED' || err == 'ASK'
        if err == 'ASK'
          asking = true
        else
          host, port = ip_and_port.split(':')
          newslot = newslot.to_i
          @slots[newslot] = { host: host, port: port, name: ip_and_port }
          @refresh_slots_cache = true
        end

        retry
      else
        raise e
      end
    end
  end

  def get_random_connection
    @startup_nodes.shuffle.each do |node|
      conn = @connections[node[:name]]
      begin
        if conn.nil?
          conn = Redis.new(node[:host], node[:port])
          if conn.ping == 'PONG'
            close_existing_connection
            @connections[node[:name]] = conn
            return conn
          else
            conn.close
          end
        else
          return conn if conn.ping == 'PONG'
        end
      rescue
        next
      end
    end
    raise 'Error: failed to get random connection'
  end

  def get_connection_by(slot)
    node = @slots[slot]
    return get_random_connection if node.nil?

    if ! @connections[node[:name]]
      close_existing_connection
      @connections[node[:name]] = Redis.new(node[:host], node[:port])
    end

    @connections[node[:name]]
  end

  def close_existing_connection
    while @connections.length > DEFAULT_MAX_CACHED_CONNECTIONS
      name, conn = @connections.shift
      conn.close
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
