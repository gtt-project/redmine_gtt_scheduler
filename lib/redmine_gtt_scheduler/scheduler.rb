module RedmineGttScheduler
  # The registry of solver backends. A backend implements
  # Adapter#solve(problem) => Solution and registers itself under a
  # name, from its own code or from another plugin's init.rb:
  #
  #   RedmineGttScheduler::Scheduler.register_adapter('my_solver', MySolverAdapter)
  #
  # The plugin settings then offer it for selection. vroom-express ships
  # with this plugin and registers itself as the default.
  module Scheduler
    DEFAULT_ADAPTER_NAME = 'vroom_express'.freeze

    def self.register_adapter(name, klass)
      adapters[name.to_s] = klass
    end

    # => {name => adapter class}, in registration order.
    def self.adapters
      @adapters ||= {}
    end

    def self.adapter_for(name)
      adapters[name.to_s]
    end
  end
end
