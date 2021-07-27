Rails.application.config.after_initialize do
  include Rate

  rate_start
end
