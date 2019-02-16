class RedisCluster

  HASH_SLOTS = 16384
  MAX_REDIRECTIONS = 16
  DEFAULT_MAX_CACHED_CONNECTIONS = 2

  def initialize(startup_nodes, options = { initialize_immediately: true })
    @startup_nodes = startup_nodes

    @nodes = {}
    @slots = {}
    @connections = {}
    @refresh_cluster_info = false

    @max_cached_connections = options[:cached_connections] || DEFAULT_MAX_CACHED_CONNECTIONS
    @logger = options[:logger]

    initialize_cluster_info unless options[:initialize_immediately] == false
  end

  def method_missing(*argv)
    send_cluster_command(argv)
  end

  def get_redis_link(node)
    Redis.new(node[:host], node[:port])
  end

  def initialize_cluster_info
    initialize_cluster_nodes
    initialize_cluster_slots
    @refresh_cluster_info = false
  end

  def cluster_slots
    @nodes.each do |_, node|
      begin
        redis = get_redis_link(node)
        return redis.cluster('slots')
      rescue => e
        log_debug("Failed to get cluster slots from #{node[:host]}:#{node[:port]} - #{e.message} (#{e.class})")
        next
      end
    end

    msg = 'Failed to get cluster slots'
    log_error(msg)
    raise msg
  end

  def initialize_cluster_nodes
    nodes = @nodes.empty? ? @startup_nodes : @nodes.values

    nodes.each do |node|
      begin
        redis = get_redis_link(node)
        resp = redis.cluster('nodes')
      rescue => e
        log_debug("Failed to get cluster nodes from #{node[:host]}:#{node[:port]} - #{e.message} (#{e.class})")
        next
      end

      resp.split("\n").each do |r|
        id, ip_port, flags = r.split(' ')
        host, port = ip_port.split(':')
        flags = flags.split(',')
        flags.delete('myself')
        if flags.include?('master') or flags.include?('slave')
          @nodes[id] = {
            host: host,
            port: port.to_i,
            name: "#{host}:#{port}",
            flags: flags
          }
        end
      end

      log_debug("Initialized cluster nodes")
      return
    end

    msg = 'Failed to get cluster nodes'
    log_error(msg)
    raise msg
  end

  def initialize_cluster_slots
    cluster_slots.each do |r|
      (r[0]..r[1]).each do |slot|
        node_id = r[2][2]
        @slots[slot] = node_id
      end
    end
    log_debug("Initialized slots cache")
  end

  def send_cluster_command(argv)
    initialize_cluster_info if @refresh_cluster_info

    try_random_connection = false
    asking = false
    num_redirects = 0

    while num_redirects < MAX_REDIRECTIONS
      num_redirects += 1

      redis =
        if try_random_connection
          try_random_connection = false
          get_random_connection
        else
          key = extract_key(argv)
          slot = hash_slot(key)
          get_connection_by(slot)
        end

      begin
        redis.asking if asking
        asking = false
        return redis.send(argv[0], *argv[1..-1])
      rescue Redis::ReplyError => e
        log_debug("Received reply error - #{e.message} (#{e.class})")
        if e.message.start_with?('MOVED')
          @refresh_cluster_info = true
          assign_redirection_node(e.message)
        elsif e.message.start_with?('ASK')
          asking = true
        else
          raise e
        end
      rescue Redis::ConnectionError => e
        log_debug("Failed to send command to #{redis.host}:#{redis.port} - #{e.message} (#{e.class})")
        close_connection(redis)
        try_random_connection = true
      end
    end

    msg = "Failed to send command. Max redirection limit exceeded (#{num_redirects} times)"
    log_error(msg)
    raise msg
  end

  def assign_redirection_node(err_msg)
    _, newslot, ip_port = err_msg.split
    host, port = ip_port.split(':')
    id, _ = @nodes.find { |k, v| v[:host] == host && v[:port] == port.to_i }
    @slots[newslot.to_i] = id
  end

  def get_random_connection
    e = nil
    @nodes.keys.shuffle.each do |node_id|
      conn = @connections[node_id]
      begin
        if conn.nil?
          node = @nodes[node_id]
          conn = get_redis_link(node)
          if conn.ping == "PONG"
            close_existing_connections
            @connections[node_id] = conn
            return conn
          else
            conn.close
          end
        else
          return conn if conn.ping == "PONG"
        end
      rescue => e
        log_debug("Failed to get connection to #{@nodes[node_id][:name]}, try with the next node - #{e.message} (#{e.class})")
        close_connection(conn) unless conn.nil?
      end
    end
    raise "Error: failed to get random connection (#{e})"
  end

  def get_connection_by(slot)
    node_id = @slots[slot]
    return get_random_connection if node_id.nil?

    unless @connections[node_id]
      close_existing_connections
      node = @nodes[node_id]
      begin
        @connections[node_id] = get_redis_link(node)
      rescue => e
        log_debug("Failed to get connection to #{node[:name]}, try to get random connection - #{e.message} (#{e.class})")
        return get_random_connection
      end
    end

    @connections[node_id]
  end

  def close_connection(conn)
    raise TypeError unless conn.instance_of?(Redis)
    log_debug("Close connection to #{conn.host}:#{conn.port}")
    @connections.delete_if { |i, c| c.host == conn.host && c.port == conn.port }
    conn.close
  end

  def close_existing_connections
    while @connections.length > @max_cached_connections
      _, conn = @connections.shift
      close_connection(conn)
    end
  end

  def close_all_connections
    @connections.each { |id, conn| close_connection(conn) }
    @connections.clear
  end

  def extract_key(argv)
    cmd = argv[0].to_s.downcase
    return nil if %w(info multi exec slaveof config shutdown).include?(cmd)
    argv[1]
  end

  def hash_slot(key)
    s = key.index("{")
    if s
      e = key.index("}", s+1)
      if e && e != s+1
        key = key[s+1..e-1]
      end
    end
    RedisClusterCRC16.crc16(key) % HASH_SLOTS
  end

  def log_error(msg)
    @logger.error(msg) if @logger
  end

  def log_debug(msg)
    @logger.debug(msg) if @logger
  end

end
