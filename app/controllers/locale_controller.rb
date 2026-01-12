class LocaleController < ApplicationController
  def switch
    locale = params[:locale]&.to_sym

    if I18n.available_locales.include?(locale)
      session[:locale] = locale
      I18n.locale = locale
    end

    redirect_back(fallback_location: root_path)
  end
end
