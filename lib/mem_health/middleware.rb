module MemHealth
  class Middleware
    include TrackingConcern

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

      request = Rack::Request.new(env)

      metrics = measure_memory do
        @status, @headers, @response = @app.call(env)
      end

      # Skip the first few requests as they have large memory jumps due to class loading
      if @@request_count > config.skip_requests
        redis.incr(redis_tracked_requests_key)
        should_track = metrics[:memory_diff] > config.memory_threshold_mb &&
                       metrics[:before] > config.ram_before_threshold_mb

        if should_track
          metadata = {
            url: request.fullpath,
            puma_thread_index: Thread.current[:puma_thread_index],
            dyno: ENV['DYNO'],
            request_method: request.request_method
          }.merge(extract_account_info(env))

          track_memory_usage(metrics[:memory_diff], metrics[:before], metrics[:after],
                           metadata.merge(execution_time: metrics[:execution_time]), type: :web)
        end
      else
        @@skipped_requests_count += 1
      end

      [@status, @headers, @response]
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

    def redis_tracked_requests_key
      self.class.redis_tracked_requests_key
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
