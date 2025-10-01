module MemHealth
  class DashboardController < ActionController::Base
    protect_from_forgery with: :exception
    layout "memhealth/application"

    def index
      @memory_hunter_enabled = MemHealth.configuration.enabled?
      @view_type = params[:view] || 'web'

      if @memory_hunter_enabled
        if @view_type == 'worker'
          @stats = MemHealth::Tracker.worker_stats
          @top_items = MemHealth::Tracker.top_memory_jobs
          @max_memory_item = MemHealth::Tracker.max_memory_job
        else
          @stats = MemHealth::Tracker.stats
          @top_items = MemHealth::Tracker.top_memory_urls
          @max_memory_item = MemHealth::Tracker.max_memory_url
        end
      else
        @stats = nil
        @top_items = []
        @max_memory_item = nil
      end
    end

    def clear
      before_stats = MemHealth::Tracker.stats
      MemHealth::Tracker.clear_all_data

      redirect_to root_path, notice: "✅ All memory usage statistics have been reset successfully! Cleared #{before_stats[:stored_urls_count]} URLs and reset max memory diff from #{before_stats[:max_memory_diff]} MB to 0.0 MB."
    rescue StandardError => e
      redirect_to root_path, alert: "❌ Error clearing memory statistics: #{e.message}"
    end

    private

    def authenticate_user!
      # Override this method in your host app if you need authentication
      # For example: authenticate_admin_user! or redirect_to login_path unless current_user&.admin?
    end
  end
end
