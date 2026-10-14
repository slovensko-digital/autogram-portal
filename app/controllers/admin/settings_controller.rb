# The admin's own page: links to the administration sections and the features of their own account.
class Admin::SettingsController < Admin::BaseController
  def show
  end

  # The admin feature always stays enabled, so an admin cannot lock themselves out here.
  def update
    features = User::AVAILABLE_FEATURES & (Array(params[:features]).map(&:to_s) | [ "admin" ])

    if current_user.update(features: features)
      redirect_to admin_settings_path, notice: t(".success")
    else
      redirect_to admin_settings_path, alert: current_user.errors.full_messages.to_sentence
    end
  end
end
