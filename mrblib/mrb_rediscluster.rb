class RedisCluster

  HASH_SLOTS = 16384
  MAX_REDIRECTIONS = 16
  DEFAULT_MAX_CACHED_CONNECTIONS = 2

  attr_reader :nodes

  def initialize(startup_nodes, max_cached_connections=nil)
    @startup_nodes = startup_nodes
    @max_cached_connections = max_cached_connections || DEFAULT_MAX_CACHED_CONNECTIONS

    @nodes = {}
    @slots = {}
    @connections = {}
    @refresh_slots_cache = false

    initialize_slots_cache
  end

  def method_missing(*argv)
    send_cluster_command(argv)
  end

  def cluster_slots
    @nodes.each do |id, node|
      begin
        redis = Redis.new(node[:host], node[:port])
        return redis.cluster('slots')
      rescue
        next
      end
    end
    raise 'Error: failed to get cluster slots'
  end

  def get_cluster_nodes(nodes)
    nodes.each do |node|
      begin
        redis = Redis.new(node[:host], node[:port])
        resp = redis.cluster('nodes')
      rescue
        next
      end

      ret = {}
      resp.split("\n").each do |r|
        id, ip_port, flags = r.split(' ')
        host, port = ip_port.split(':')
        flags = flags.split(',')
        flags.delete('myself')
        ret[id] = {
          host: host,
          port: port.to_i,
          name: "#{host}:#{port}",
          flags: flags
        }
      end
      return ret
    end
    raise 'Error: failed to get cluster nodes'
  end

  def initialize_slots_cache
    @nodes = if @nodes.empty?
        get_cluster_nodes(@startup_nodes)
      else
        get_cluster_nodes(@nodes.values)
      end

    cluster_slots.each do |r|
      (r[0]..r[1]).each do |slot|
        node_id = r[2][2]
        @slots[slot] = node_id
      end
    end

    @refresh_slots_cache = false
  end

  def send_cluster_command(argv)
    initialize_slots_cache if @refresh_slots_cache

    try_random_connection = false
    asking = false
    num_redirects = 0

    while num_redirects < MAX_REDIRECTIONS
      num_redirects += 1

      key = extract_key(argv)
      slot = hash_slot(key)

      if try_random_connection
        redis = get_random_connection
        try_random_connection = false
      else
        redis = get_connection_by(slot)
      end

      begin
        redis.asking if asking
        asking = false
        return redis.send(argv[0], *argv[1..-1])
      rescue Redis::ReplyError => e
        if e.message.start_with?('MOVED')
          @refresh_slots_cache = true
          err, newslot, ip_port = e.message.split
          host, port = ip_port.split(':')
          port = port.to_i
          newslot = newslot.to_i
          id, node = @nodes.find { |k, v| v[:host] == host && v[:port] == port.to_i }
          @slots[newslot] = id
        elsif e.message.start_with?('ASK')
          asking = true
        else
          raise e
        end
      rescue Redis::ConnectionError => e
        try_random_connection = true
      end
    end
    raise "Error: #{argv[0]} #{argv[1..-1].join(' ')} - max redirection limit exceeded (#{MAX_REDIRECTIONS} times)"
  end

  def get_random_connection
    e = nil
    @nodes.keys.shuffle.each do |node_id|
      conn = @connections[node_id]
      begin
        if conn.nil?
          node = @nodes[node_id]
          conn = Redis.new(node[:host], node[:port])
          if conn.ping == "PONG"
            close_existing_connection
            @connections[node_id] = conn
            return conn
          else
            conn.close
          end
        else
          return conn if conn.ping == "PONG"
        end
      rescue => e
        # Just try with the next node.
      end
    end
    raise "Error: failed to get random connection (#{e})"
  end

  def get_connection_by(slot)
    node_id = @slots[slot]
    return get_random_connection if node_id.nil?

    if ! @connections[node_id]
      close_existing_connection
      node = @nodes[node_id]
      @connections[node_id] = Redis.new(node[:host], node[:port])
    end

    @connections[node_id]
  end

  def close_existing_connection
    while @connections.length > DEFAULT_MAX_CACHED_CONNECTIONS
      id, conn = @connections.shift
      conn.close
    end
  end

  def close_all_connections
    @connections.each do |id, conn|
      conn.close
    end
    @connections.clear
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
