module RecipientsHelper
  def recipient_status_badge(recipient)
    colors = {
      pending: { bg: "bg-blue-100", text: "text-blue-800" },
      sending: { bg: "bg-blue-100", text: "text-blue-800" },
      notified: { bg: "bg-yellow-100", text: "text-yellow-800" },
      signed: { bg: "bg-green-100", text: "text-green-800" },
      declined: { bg: "bg-red-100", text: "text-red-800" }
    }

    status = recipient.status.to_sym
    color = colors[status]

    content_tag :span,
      t("helpers.recipients.status.#{status}"),
      class: "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium #{color[:bg]} #{color[:text]}"
  end
end
