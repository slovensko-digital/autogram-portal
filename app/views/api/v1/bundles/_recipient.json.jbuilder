json.name recipient.name
json.email recipient.email
json.uuid recipient.uuid
signing_status = recipient.signing_status
json.state signing_status == :pending ? "awaiting" : signing_status.to_s
json.notified_at recipient.notified_at
