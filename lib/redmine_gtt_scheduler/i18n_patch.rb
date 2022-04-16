require_dependency 'i18n'

module RedmineGttScheduler
  module I18nPatch
    def self.prepended(base)
      base.module_eval do
        def format_datetime(time)
          return nil unless time

          user ||= User.current
          options = {}
          options[:format] = (Setting.time_format.blank? ? :time : Setting.time_format)
          time = time.to_time if time.is_a?(String)
          local = user.convert_time_to_user_timezone(time)
          local.strftime('%Y-%m-%dT%H:%M:%S')
        end
      end
    end
  end
end

Redmine::I18n.prepend(RedmineGttScheduler::I18nPatch)
