json.id @bundle.uuid
json.contracts @bundle.contracts, partial: "api/v1/contracts/contract", as: :contract
json.recipients @bundle.recipients, partial: "api/v1/bundles/recipient", as: :recipient if @bundle.recipients.any?
json.webhook @bundle.webhook, partial: "api/v1/bundles/webhook", as: :webhook if @bundle.webhook.present?
json.postal_address @bundle.postal_address, partial: "api/v1/bundles/postal_address", as: :postal_address if @bundle.postal_address.present?
json.created_at @bundle.created_at
