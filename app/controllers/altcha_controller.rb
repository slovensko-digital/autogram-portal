# frozen_string_literal: true

class AltchaController < ApplicationController
  def challenge
    render json: AltchaService.create_challenge(hmac_key: altcha_hmac_key)
  end

  private

  def altcha_hmac_key
    Rails.application.credentials.altcha_hmac_key.presence ||
      ENV.fetch("ALTCHA_HMAC_KEY") { raise "ALTCHA_HMAC_KEY is not set" }
  end
end
