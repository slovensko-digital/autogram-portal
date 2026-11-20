class Current < ActiveSupport::CurrentAttributes
  # How the request reached the portal: "api" in ApiController, nil on the web. Recorded in ActivityEvent.
  attribute :channel
end
