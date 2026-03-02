module Contracts
  class OnboardingController < ApplicationController
    before_action :set_contract
    before_action :set_recipient
    before_action :validate_method_param
    before_action :check_onboarding_status
    before_action :allow_iframe
    skip_before_action :verify_authenticity_token

    VALID_STEPS = %w[qscd_check legacy_eid_card pin_check certificate_check physical_instructions].freeze

    def show
      @step = step_param || first_step
      @method = params[:method] # 'electronic' or 'physical'

      render @step
    end

    def update
      @method = params[:method]
      @step = step_param

      case @step
      when "qscd_check"
        handle_qscd_check
      when "pin_check"
        handle_pin_check
      when "certificate_check"
        handle_certificate_check
      when "physical_instructions"
        handle_physical_instructions
      else
        redirect_to contract_onboarding_path(@contract, step: first_step, method: @method, iframe: params[:iframe])
      end
    end

    private

    def set_contract
      @contract = Contract.find_by!(uuid: params[:contract_id])
    end

    def set_recipient
      if params[:recipient]
        @recipient = @contract.recipients.find_by(uuid: params[:recipient])
      elsif current_user
        @recipient = @contract.recipients.find_by(email: current_user.email)
      end
    end

    def validate_method_param
      @method = params[:method]
      unless %w[electronic physical].include?(@method)
        redirect_to sign_contract_path(@contract, iframe: params[:iframe])
      end
    end

    def check_onboarding_status
      return if params[:skip] == "true"

      return if params[:review] == "true"

      if current_user&.onboarding_completed?(@method)
        redirect_to_next_page
      end
    end

    def handle_qscd_check
      qscd = params[:qscd]
      unless qscd.in?(User.qscds.keys)
        return redirect_to contract_onboarding_path(@contract, step: "qscd_check", method: @method, recipient: @recipient&.uuid, iframe: params[:iframe]),
                  flash: { alert: I18n.t("contracts.onboarding.qscd_check.invalid_selection") }
      end

      current_user.update!(qscd: qscd) if current_user
      session[:qscd] = qscd unless current_user

      if User.legacy_eid_card?(qscd)
        return redirect_to contract_onboarding_path(@contract, step: "legacy_eid_card", method: @method, review: params[:review], recipient: @recipient&.uuid, iframe: params[:iframe])
      end

      redirect_to contract_onboarding_path(@contract, step: "pin_check", method: @method, review: params[:review], recipient: @recipient&.uuid, iframe: params[:iframe])
    end

    def handle_pin_check
      redirect_to contract_onboarding_path(@contract, step: "certificate_check", method: @method, review: params[:review], recipient: @recipient&.uuid, iframe: params[:iframe])
    end

    def handle_certificate_check
      if current_user
        current_user.mark_onboarding_complete!(@method)
      else
        session[:completed_onboardings] ||= []
        session[:completed_onboardings] << @method unless session[:completed_onboardings].include?(@method)
      end

      redirect_to_next_page
    end

    def handle_physical_instructions
      if current_user
        current_user.mark_onboarding_complete!(@method)
      else
        session[:completed_onboardings] ||= []
        session[:completed_onboardings] << @method unless session[:completed_onboardings].include?(@method)
      end

      redirect_to_next_page
    end

    def redirect_to_next_page
      case @method
      when "electronic"
        qscd = current_user&.qscd || session[:qscd]
        redirect_to signature_apps_contract_path(@contract, recipient: @recipient&.uuid, qscd: qscd, iframe: params[:iframe])
      when "physical"
        redirect_to physical_signing_contract_path(@contract, recipient: @recipient&.uuid, iframe: params[:iframe])
      end
    end

    def first_step
      case @method
      when "electronic"
        "qscd_check"
      when "physical"
        "physical_instructions"
      end
    end

    def step_param
      VALID_STEPS.include?(params[:step]) ? params[:step] : nil
    end
  end
end
