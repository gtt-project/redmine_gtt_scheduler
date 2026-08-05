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

    # Re-registering a name with a different class is logged: two plugins
    # fighting over one name is a misconfiguration that would otherwise
    # be invisible (last load order wins). Compared by class name, not
    # identity, because a development reload recreates the class object.
    def self.register_adapter(name, klass)
      existing = adapters[name.to_s]
      if existing && existing.name != klass.name
        Rails.logger.warn(
          "[Scheduler] solver backend #{name.inspect} re-registered: " \
          "#{existing.name} replaced by #{klass.name}"
        )
      end
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
