module MemHealth
  class JobTrackingMiddleware
    include TrackingConcern

    def call(worker, job, queue, &block)
      return yield unless config.enabled?

      metrics = measure_memory(&block)

      # Track if memory usage is significant
      unless metrics[:memory_diff] > config.memory_threshold_mb && metrics[:before] > config.ram_before_threshold_mb
        return
      end

      related_model = extract_related_model(job)
      job_class = extract_job_class(worker, job)

      metadata = {
        worker_class: related_model ? "#{job_class} (#{related_model})" : job_class,
        queue: queue,
        dyno: ENV['DYNO'],
        job_id: job['jid'],
        job_args: extract_job_args(job)
      }

      track_memory_usage(metrics[:memory_diff], metrics[:before], metrics[:after],
                         metadata.merge(execution_time: metrics[:execution_time]), type: :worker)
    end

    private

    def extract_job_class(worker, job)
      # For ActiveJob jobs, extract the actual job class from the wrapper
      if worker.class.name == 'ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper'
        job['wrapped'] || job['args']&.first&.dig('job_class') || worker.class.name
      else
        worker.class.name
      end
    end

    def extract_job_args(job)
      # Extract arguments, limiting size to avoid storing huge data
      args = if job['wrapped'] # ActiveJob
               job['args']&.first&.dig('arguments')
             else # Native Sidekiq
               job['args']
             end

      return nil unless args

      # Convert to string and truncate if too long
      args_string = args.inspect
      args_string.length > 2000 ? "#{args_string[0..1970]}..." : args_string
    rescue StandardError
      nil
    end

    def extract_related_model(job)
      # Try to find related model from job arguments
      args = if job['wrapped'] # ActiveJob
               job['args']&.first&.dig('arguments')
             else
               job['args']
             end

      return nil unless args

      # Look for GlobalID patterns that indicate the actual model being processed
      global_ids = extract_global_ids(args)
      return nil if global_ids.empty?

      # Return the first non-ActiveJob related model
      global_ids.first
    rescue StandardError
      nil
    end

    def extract_global_ids(obj, results = [])
      case obj
      when Hash
        if obj['_aj_globalid']
          # Extract model class from GlobalID (e.g., "gid://app/ModelName/123" -> "ModelName")
          gid = obj['_aj_globalid']
          if gid =~ %r{gid://[^/]+/([^/]+)/}
            model_name = $1
            results << model_name unless results.include?(model_name)
          end
        else
          obj.each_value { |v| extract_global_ids(v, results) }
        end
      when Array
        obj.each { |v| extract_global_ids(v, results) }
      end
      results
    end
  end
end
