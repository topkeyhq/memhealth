module MemHealth
  class Tracker
    class << self
      # Get the maximum memory difference recorded
      def max_memory_diff
        redis.get(redis_max_diff_key)&.to_f || 0.0
      end

      # Get all stored URLs, ordered by memory usage (highest first)
      def top_memory_urls(limit: config.max_stored_urls)
        redis.zrevrange(redis_high_usage_urls_key, 0, limit - 1, with_scores: true).map do |json_data, score|
          data = JSON.parse(json_data)
          data.merge("memory_diff" => score)
        end
      end

      # Alias for backward compatibility
      alias_method :high_usage_urls, :top_memory_urls

      # Get URLs that used more than a specific threshold
      def urls_above_threshold(threshold_mb)
        redis.zrangebyscore(redis_high_usage_urls_key, threshold_mb, "+inf", with_scores: true).map do |json_data, score|
          data = JSON.parse(json_data)
          data.merge("memory_diff" => score)
        end
      end

      # Get the URL with the highest memory usage (the one that set the max diff)
      def max_memory_url
        json_data = redis.get(redis_max_diff_url_key)
        return nil if json_data.nil?

        JSON.parse(json_data)
      end

      # Clear all memory tracking data
      def clear_all_data
        redis.del(redis_max_diff_key, redis_max_diff_url_key, redis_high_usage_urls_key)
        MemHealth::Middleware.reset_data
      end

      # Get stats summary
      def stats
        max_diff = max_memory_diff
        stored_urls_count = redis.zcard(redis_high_usage_urls_key)
        tracked_count = MemHealth::Middleware.tracked_requests_count
        total_count = MemHealth::Middleware.total_requests_count
        skipped_count = MemHealth::Middleware.skipped_requests_count

        {
          max_memory_diff: max_diff,
          stored_urls_count: stored_urls_count,
          max_stored_urls: config.max_stored_urls,
          tracked_requests_count: tracked_count,
          total_requests_count: total_count,
          skipped_requests_count: skipped_count,
          requests_tracked: "#{tracked_count} requests tracked (#{skipped_count} skipped) out of #{total_count} total requests"
        }
      end

      # Pretty print stats for console use
      def print_stats
        stats_data = stats
        puts "\n=== Memory Usage Stats ==="
        puts "Max memory difference: #{stats_data[:max_memory_diff]} MB"
        puts "Stored URLs: #{stats_data[:stored_urls_count]}/#{stats_data[:max_stored_urls]}"
        puts "Tracking: #{stats_data[:requests_tracked]}"

        if stats_data[:stored_urls_count] > 0
          puts "\nTop 10 memory usage URLs:"
          top_memory_urls(limit: 10).each_with_index do |url_data, index|
            if url_data["ram_before"] && url_data["ram_after"]
              puts "#{index + 1}. #{url_data["memory_diff"]} MB (#{url_data["ram_before"]} → #{url_data["ram_after"]} MB) - #{url_data["url"]} (#{url_data["recorded_at"]})"
            else
              puts "#{index + 1}. #{url_data["memory_diff"]} MB - #{url_data["url"]} (#{url_data["recorded_at"]})"
            end
          end
        end
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
    end
  end
end
