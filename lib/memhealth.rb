require "mem_health/version"
require "mem_health/configuration"
require "mem_health/tracking_concern"
require "mem_health/middleware"
require "mem_health/job_tracking_middleware"
require "mem_health/tracker"
require "mem_health/engine"

module MemHealth
  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end
  end
end

