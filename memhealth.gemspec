require_relative "lib/mem_health/version"

Gem::Specification.new do |spec|
  spec.name = "memhealth"
  spec.version = MemHealth::VERSION
  spec.authors = ["Klemen Nagode"]
  spec.email = ["klemen@topkey.io"]
  spec.homepage = "https://github.com/topkeyhq/memhealth"
  spec.summary = "Rails memory health monitoring and tracking"
  spec.description = "A Rails engine for monitoring memory health and detecting growth patterns in production applications"
  spec.license = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/topkeyhq/memhealth"

  spec.files = Dir["{app,config,lib}/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 6.0"
  spec.add_dependency "redis"
  spec.add_dependency "get_process_mem"

  spec.add_development_dependency "rspec-rails"
end
