# Add schedule button at the end of issues table
Deface::Override.new(
  :virtual_path => "issues/index",
  :name => "deface_view_issues_schedule_button",
  :insert_before => ".pagination",
  :original => "738883a3c4c550a254b6062bf96c9b123b5094be",
  :partial => "issues/index/schedule_button"
)

# Change start date to datetime field with datetime picker in form mode
Deface::Override.new(
  :virtual_path => "issues/_attributes",
  :name => "deface_issue_modify_start_date_form_mode",
  :replace => "#start_date_area",
  :original => "e332001735bce56e683157eda1a49da963297a8c",
  :partial => "issues/index/start_date_form"
)

# Change due date to datetime field with datetime picker in form mode
Deface::Override.new(
  :virtual_path => "issues/_attributes",
  :name => "deface_issue_modify_due_date_form_mode",
  :replace => "#due_date_area",
  :original => "12c8164ac5881498302c6f11cf8a1067da1d21df",
  :partial => "issues/index/due_date_form"
)

# Display date and time for start date in view mode.
# For due date, need to modify issue_due_date_details method in issues_helper
Deface::Override.new(
  :virtual_path => "issues/show",
  :name => "deface_issue_modify_start_date_view_mode",
  :replace => "erb[loud]:contains('issue_fields_rows')",
  :original => "24eca8b146c886379b2f57b718beace8350f71b4",
  :partial => "issues/index/show"
)
