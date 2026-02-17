module Contracts
  class OnboardingController < ApplicationController
    before_action :set_contract
    before_action :set_recipient
    before_action :validate_method_param
    before_action :check_onboarding_status
    before_action :allow_iframe
    skip_before_action :verify_authenticity_token

    VALID_STEPS = %w[eid_card_generation pin_check certificate_check physical_instructions].freeze

    def show
      @step = step_param || first_step
      @method = params[:method] # 'electronic' or 'physical'

      render "contracts/onboarding/show"
    end

    def update
      @method = params[:method]
      @step = step_param

      case @step
      when "eid_card_generation"
        handle_eid_card_generation
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

    def handle_eid_card_generation
      if params.require(:eid_card_generation).in?(User.eid_card_generations.keys)
        if current_user
          current_user.update!(eid_card_generation: params[:eid_card_generation])
        else
          session[:eid_card_generation] = params[:eid_card_generation]
        end

        redirect_to contract_onboarding_path(@contract, step: "pin_check", method: @method, review: params[:review], recipient: @recipient&.uuid, iframe: params[:iframe])
      else
        redirect_to contract_onboarding_path(@contract, step: "eid_card_generation", method: @method, recipient: @recipient&.uuid, iframe: params[:iframe]),
                    alert: "Please select your eID card generation"
      end
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
        generation = current_user&.eid_card_generation || session[:eid_card_generation]
        redirect_to signature_apps_contract_path(@contract, recipient: @recipient&.uuid, eid_card_generation: generation, iframe: params[:iframe])
      when "physical"
        redirect_to physical_signing_contract_path(@contract, recipient: @recipient&.uuid, iframe: params[:iframe])
      end
    end

    def first_step
      case @method
      when "electronic"
        "eid_card_generation"
      when "physical"
        "physical_instructions"
      end
    end

    def step_param
      VALID_STEPS.include?(params[:step]) ? params[:step] : nil
    end
  end
end
