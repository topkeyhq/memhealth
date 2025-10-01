require 'get_process_mem'

module MemHealth
  module TrackingConcern
    private

    def config
      MemHealth.configuration
    end

    def redis
      config.redis
    end

    def track_memory_usage(memory_diff, ram_before, ram_after, metadata, type: :web)
      prefix = type == :worker ? 'worker:' : ''

      # Update max memory diff seen so far
      max_diff_key = "#{config.redis_key_prefix}:#{prefix}max_diff"
      max_item_key = "#{config.redis_key_prefix}:#{prefix}max_diff_#{type == :worker ? 'job' : 'url'}"
      high_usage_key = "#{config.redis_key_prefix}:#{prefix}high_usage_#{type == :worker ? 'jobs' : 'urls'}"

      current_max = redis.get(max_diff_key)&.to_f || 0.0
      if memory_diff > current_max
        redis.set(max_diff_key, memory_diff)

        # Store the item data that caused the maximum memory usage
        max_item_data = {
          memory_diff: memory_diff,
          ram_before: ram_before,
          ram_after: ram_after,
          timestamp: Time.current.to_i,
          recorded_at: Time.current.iso8601
        }.merge(metadata)
        redis.set(max_item_key, max_item_data.to_json)
      end

      # Store all items
      item_data = {
        memory_diff: memory_diff,
        ram_before: ram_before,
        ram_after: ram_after,
        timestamp: Time.current.to_i,
        recorded_at: Time.current.iso8601
      }.merge(metadata)

      # Add item to sorted set (score = memory_diff for DESC ordering)
      redis.zadd(high_usage_key, memory_diff, item_data.to_json)

      # Keep only top N items by removing lowest scores
      current_count = redis.zcard(high_usage_key)
      return unless current_count > config.max_stored_urls

      # Remove the lowest scoring items (keep top max_stored_urls)
      redis.zremrangebyrank(high_usage_key, 0, current_count - config.max_stored_urls - 1)
    end

    def measure_memory
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      before = GetProcessMem.new.mb

      yield

      after = GetProcessMem.new.mb
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      execution_time = (end_time - start_time).round(2)
      memory_diff = (after - before).round(2)

      {
        before: before.round(2),
        after: after.round(2),
        memory_diff: memory_diff,
        execution_time: execution_time
      }
    end
  end
end
