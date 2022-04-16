# Configure View Overrides
Rails.application.paths["app/overrides"] ||= []
Rails.application.paths["app/overrides"] << File.expand_path("../app/overrides", __FILE__)

Redmine::Plugin.register :redmine_gtt_scheduler do
  name 'Redmine GTT Scheduler plugin'
  author 'Georepublic'
  description 'Schedules the issues created in Redmine'
  version '0.0.1'
  url 'https://github.com/gtt-project/redmine_gtt_scheduler'
  author_url 'https://github.com/Georepublic'

  requires_redmine :version_or_higher => '4.0.0'

  requires_redmine_plugin :redmine_gtt, :version_or_higher => '2.1.0'
  requires_redmine_plugin :redmine_datetime_custom_field, :version_or_higher => '1.0.4'

  project_module :gtt_scheduler do

  end
end

require_dependency 'redmine_gtt_scheduler/hooks'

Rails.application.config.to_prepare do
  require_dependency 'redmine_gtt_scheduler/issue_patch'
  require_dependency 'redmine_gtt_scheduler/i18n_patch'
  require_dependency 'redmine_gtt_scheduler/issues_helper_patch'
end
