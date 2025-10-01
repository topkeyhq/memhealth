module MemHealth
  class Tracker
    class << self
      # Generic methods for web and worker tracking
      def max_memory_diff(type: :web)
        key = type == :worker ? redis_max_diff_worker_key : redis_max_diff_key
        redis.get(key)&.to_f || 0.0
      end

      def top_memory_items(type: :web, limit: config.max_stored_urls)
        key = type == :worker ? redis_high_usage_jobs_key : redis_high_usage_urls_key
        redis.zrevrange(key, 0, limit - 1, with_scores: true).map do |json_data, score|
          data = JSON.parse(json_data)
          data.merge("memory_diff" => score)
        end
      end

      def items_above_threshold(threshold_mb, type: :web)
        key = type == :worker ? redis_high_usage_jobs_key : redis_high_usage_urls_key
        redis.zrangebyscore(key, threshold_mb, "+inf", with_scores: true).map do |json_data, score|
          data = JSON.parse(json_data)
          data.merge("memory_diff" => score)
        end
      end

      def max_memory_item(type: :web)
        key = type == :worker ? redis_max_diff_job_key : redis_max_diff_url_key
        json_data = redis.get(key)
        return nil if json_data.nil?

        JSON.parse(json_data)
      end

      # Convenience methods with backward compatibility
      def max_memory_diff_worker
        max_memory_diff(type: :worker)
      end

      def top_memory_urls(limit: config.max_stored_urls)
        top_memory_items(type: :web, limit: limit)
      end

      alias_method :high_usage_urls, :top_memory_urls

      def top_memory_jobs(limit: config.max_stored_urls)
        top_memory_items(type: :worker, limit: limit)
      end

      def urls_above_threshold(threshold_mb)
        items_above_threshold(threshold_mb, type: :web)
      end

      def jobs_above_threshold(threshold_mb)
        items_above_threshold(threshold_mb, type: :worker)
      end

      def max_memory_url
        max_memory_item(type: :web)
      end

      def max_memory_job
        max_memory_item(type: :worker)
      end

      # Clear all memory tracking data
      def clear_all_data
        redis.del(redis_max_diff_key, redis_max_diff_url_key, redis_high_usage_urls_key,
                  redis_max_diff_worker_key, redis_max_diff_job_key, redis_high_usage_jobs_key)
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

      # Get worker stats summary
      def worker_stats
        max_diff = max_memory_diff_worker
        stored_jobs_count = redis.zcard(redis_high_usage_jobs_key)

        {
          max_memory_diff: max_diff,
          stored_jobs_count: stored_jobs_count,
          max_stored_jobs: config.max_stored_urls
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

      def redis_max_diff_worker_key
        "#{config.redis_key_prefix}:worker:max_diff"
      end

      def redis_max_diff_job_key
        "#{config.redis_key_prefix}:worker:max_diff_job"
      end

      def redis_high_usage_jobs_key
        "#{config.redis_key_prefix}:worker:high_usage_jobs"
      end
    end
  end
end
