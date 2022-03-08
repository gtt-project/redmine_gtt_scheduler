Redmine::Plugin.register :redmine_gtt_scheduler do
  name 'Redmine GTT Scheduler plugin'
  author 'Georepublic'
  description 'Schedules the issues created in Redmine'
  version '0.0.1'
  url 'https://github.com/gtt-project/redmine_gtt_scheduler'
  author_url 'https://github.com/Georepublic'

  requires_redmine :version_or_higher => '4.0.0'
end
