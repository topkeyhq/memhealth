require 'get_process_mem'

module MemHealth
  class Middleware
    @@request_count = 0
    @@skipped_requests_count = 0

    def self.redis_tracked_requests_key
      "#{MemHealth.configuration.redis_key_prefix}:tracked_requests"
    end

    def initialize(app)
      @app = app
    end

    def call(env)
      @@request_count += 1

      # Track execution time
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      before = GetProcessMem.new.mb
      status, headers, response = @app.call(env)
      after = GetProcessMem.new.mb

      # Calculate execution time in seconds
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      execution_time = (end_time - start_time).round(2)

      memory_diff = (after - before).round(2)
      request = Rack::Request.new(env)
      request_url = request.fullpath
      account_info = extract_account_info(env)

      # Collect additional metadata
      metadata = {
        puma_thread_index: Thread.current[:puma_thread_index],
        dyno: ENV['DYNO'],
        execution_time: execution_time,
        request_method: request.request_method
      }

      # Skip the first few requests as they have large memory jumps due to class loading
      if @@request_count > config.skip_requests
        redis.incr(redis_tracked_requests_key)
        should_track = memory_diff > config.memory_threshold_mb && before.round(2) > config.ram_before_threshold_mb
        if should_track
          track_memory_usage(memory_diff, request_url, before.round(2), after.round(2),
                             account_info.merge(metadata))
        end
      else
        @@skipped_requests_count += 1
      end

      [status, headers, response]
    end

    def self.reset_data
      @@request_count = 0
      @@skipped_requests_count = 0
      MemHealth.configuration.redis.del(redis_tracked_requests_key)
    end

    def self.tracked_requests_count
      MemHealth.configuration.redis.get(redis_tracked_requests_key)&.to_i || 0
    end

    def self.total_requests_count
      @@request_count
    end

    def self.skipped_requests_count
      @@skipped_requests_count
    end

    private

    def config
      MemHealth.configuration
    end

    def redis
      config.redis
    end

    def redis_max_diff_key
      "#{config.redis_key_prefix}:max_diff"
    end

    def redis_max_diff_url_key
      "#{config.redis_key_prefix}:max_diff_url"
    end

    def redis_high_usage_urls_key
      "#{config.redis_key_prefix}:high_usage_urls"
    end

    def redis_tracked_requests_key
      self.class.redis_tracked_requests_key
    end

    def track_memory_usage(memory_diff, request_url, ram_before, ram_after, request_metadata = {})
      # Update max memory diff seen so far
      current_max = redis.get(redis_max_diff_key)&.to_f || 0.0
      if memory_diff > current_max
        redis.set(redis_max_diff_key, memory_diff)

        # Store the URL data that caused the maximum memory usage
        max_url_data = {
          url: request_url,
          memory_diff: memory_diff,
          ram_before: ram_before,
          ram_after: ram_after,
          timestamp: Time.current.to_i,
          recorded_at: Time.current.iso8601
        }.merge(request_metadata)
        redis.set(redis_max_diff_url_key, max_url_data.to_json)
      end

      # Store all URLs
      timestamp = Time.current.to_i
      url_data = {
        url: request_url,
        memory_diff: memory_diff,
        ram_before: ram_before,
        ram_after: ram_after,
        timestamp: timestamp,
        recorded_at: Time.current.iso8601
      }.merge(request_metadata)

      # Add URL to sorted set (score = memory_diff for DESC ordering)
      redis.zadd(redis_high_usage_urls_key, memory_diff, url_data.to_json)

      # Keep only top N URLs by removing lowest scores
      current_count = redis.zcard(redis_high_usage_urls_key)
      return unless current_count > config.max_stored_urls

      # Remove the lowest scoring URLs (keep top max_stored_urls)
      redis.zremrangebyrank(redis_high_usage_urls_key, 0, current_count - config.max_stored_urls - 1)
    end

    def extract_account_info(env)
      account_info = {}

      begin
        # Try to get account info from various sources
        if defined?(ActsAsTenant) && ActsAsTenant.current_tenant
          account = ActsAsTenant.current_tenant
          account_info[:account_id] = account.id
        elsif env['warden']&.user&.respond_to?(:account)
          # Try to get from authenticated user
          account = env['warden'].user.account
          account_info[:account_id] = account.id
        elsif env['HTTP_X_ACCOUNT_ID']
          # Fallback to header if available
          account_info[:account_id] = env['HTTP_X_ACCOUNT_ID']
        end
      rescue StandardError => _e
        # Silently fail if account extraction fails
      end

      account_info
    end
  end
end
