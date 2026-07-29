module SchedulerRunsHelper
  def scheduler_time(timestamp)
    return '-' if timestamp.nil?

    timestamp.in_time_zone(RedmineGttScheduler.reference_zone).strftime('%H:%M')
  end

  def scheduler_travel(seconds)
    return '-' if seconds.nil?

    "#{(seconds / 60.0).round} min"
  end

  def scheduler_run_status(run)
    content_tag(:span, l(:"label_scheduler_status_#{run.status}"),
                class: "scheduler-status scheduler-status-#{run.status}")
  end
end
