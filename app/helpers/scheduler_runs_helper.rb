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

  # Hour ticks and per-assignment bars for the timeline, as percentages of the
  # window so the markup needs no pixel arithmetic. The window is whole hours
  # covering every assignment, which keeps rows of different resources aligned
  # on the same axis.
  def scheduler_timeline(assignments)
    times = assignments.flat_map { |a| [a.starts_at, a.ends_at] }.compact
    return nil if times.empty?

    zone = RedmineGttScheduler.reference_zone
    from = times.min.in_time_zone(zone).change(min: 0)
    to = times.max.in_time_zone(zone)
    to = to.change(min: 0) + 1.hour if to.min.positive? || to == from
    span = (to - from).to_f
    return nil unless span.positive?

    {
      from: from,
      to: to,
      hours: ((to - from) / 1.hour).round,
      ticks: scheduler_timeline_ticks(from, to, span),
      bars: assignments.map { |a| scheduler_timeline_bar(a, from, span) }
    }
  end

  private

  def scheduler_timeline_ticks(from, to, span)
    ticks = []
    at = from
    while at <= to
      ticks << {label: at.strftime('%H:%M'), left: ((at - from) / span * 100).round(4)}
      at += 1.hour
    end
    ticks
  end

  def scheduler_timeline_bar(assignment, from, span)
    left = ((assignment.starts_at - from) / span * 100).round(4)
    width = ((assignment.ends_at - assignment.starts_at) / span * 100).round(4)
    {
      assignment: assignment,
      left: left.clamp(0, 100),
      # Keep a hairline visible for a zero-duration stop rather than nothing.
      width: width.clamp(0.4, 100 - left.clamp(0, 100))
    }
  end
end
