# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]

# Request logs hold no documents, no data of people and no signing links. Symbols match a part of the
# parameter name (and hide such attributes in #inspect of records), the patterns only the whole name,
# so that identifiers such as recipient_uuid or document_id stay readable.
Rails.application.config.filter_parameters += [
  :name, :phone, :code, :url, :note, :signed_id, :custom_text, :drawing_data,
  /\A(signed_)?documents?\z/, /\Arecipients?\z/, /\A(content|file|blob|image|text|q)\z/
]
