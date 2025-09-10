require "redis"

module MemHealth
  class Configuration
    attr_accessor :enabled,
      :skip_requests,
      :memory_threshold_mb,
      :ram_before_threshold_mb,
      :max_stored_urls,
      :redis_url,
      :redis_key_prefix

    def initialize
      @enabled = ENV.fetch("MEM_HEALTH_ENABLED", "false") == "true"
      @skip_requests = ENV.fetch("MEM_HEALTH_SKIP_REQUESTS", "10").to_i
      @memory_threshold_mb = ENV.fetch("MEM_HEALTH_MEMORY_THRESHOLD_MB", "1").to_i
      @ram_before_threshold_mb = ENV.fetch("MEM_HEALTH_RAM_BEFORE_THRESHOLD", "0").to_i
      @max_stored_urls = ENV.fetch("MEM_HEALTH_MAX_STORED_URLS", "20").to_i
      redis_env_key = ENV.fetch("MEM_HEALTH_REDIS_KEY", "REDIS_URL")
      @redis_url = ENV.fetch(redis_env_key, "redis://localhost:6379/0")
      @redis_key_prefix = "memhealth"
    end

    def enabled?
      @enabled
    end

    def redis
      @redis ||= Redis.new(url: redis_url)
    end
  end
end
