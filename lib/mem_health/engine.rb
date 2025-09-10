module MemHealth
  class Engine < ::Rails::Engine
    isolate_namespace MemHealth
    
    # Set specific autoload paths and exclude others
    config.autoload_paths += %W(#{root}/app/controllers #{root}/app/views)
    config.eager_load_paths += %W(#{root}/app/controllers #{root}/app/views)
    
    # Configure Zeitwerk to ignore config and lib directories
    initializer "mem_health.zeitwerk_ignore", before: :set_autoload_paths do
      config.autoload_paths.delete("#{root}/config")
      config.autoload_paths.delete("#{root}/lib")
      
      if defined?(Rails.autoloaders)
        Rails.autoloaders.main.ignore("#{root}/config")
        Rails.autoloaders.main.ignore("#{root}/lib")
      end
    end
    
    config.generators do |g|
      g.test_framework :rspec
    end

    initializer "mem_health.load_controllers", after: :load_config_initializers do
      # Manually require the controller to ensure it loads
      begin
        require File.join(root, "app", "controllers", "mem_health", "dashboard_controller")
      rescue => e
        Rails.logger.warn "Could not load MemHealth controller: #{e.message}" if defined?(Rails.logger)
      end
    end

    initializer "mem_health.middleware", before: :build_middleware_stack do |app|
      if MemHealth.configuration.enabled?
        require "get_process_mem"
        app.config.middleware.use MemHealth::Middleware
      end
    end
  end
end
