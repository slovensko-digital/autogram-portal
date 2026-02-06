module Contracts
  class OnboardingController < ApplicationController
    before_action :set_contract
    before_action :set_recipient
    before_action :set_bundle
    before_action :validate_method_param
    before_action :check_onboarding_status

    # GET /contracts/:contract_id/onboarding/:step
    def show
      @step = params[:step] || first_step
      @method = params[:method] # 'electronic' or 'physical'

      render "contracts/onboarding/show"
    end

    # PATCH/PUT /contracts/:contract_id/onboarding/:step
    def update
      @method = params[:method]
      @step = params[:step]

      case @step
      when 'eid_card_generation'
        handle_eid_card_generation
      when 'pin_check'
        handle_pin_check
      when 'certificate_check'
        handle_certificate_check
      when 'physical_instructions'
        handle_physical_instructions
      else
        redirect_to contract_onboarding_path(@contract, step: first_step, method: @method), alert: 'Invalid step'
      end
    end

    private

    def set_contract
      @contract = Contract.find_by!(uuid: params[:contract_id])
    end

    def set_recipient
      # Priority: URL param (magic link) > current user email match
      # NEVER use session for recipient - it's identity, not navigation state
      if params[:recipient]
        @recipient = @contract.recipients.find_by(uuid: params[:recipient])
      elsif current_user
        # Logged-in user: find their recipient by email match
        @recipient = @contract.recipients.find_by(email: current_user.email)
      end
    end

    def set_bundle
      # Bundle context is derived from @contract.bundle in views
      # No need to track bundle_id through params/session
    end

    def validate_method_param
      @method = params[:method]
      unless %w[electronic physical].include?(@method)
        redirect_to sign_contract_path(@contract), alert: 'Invalid signing method'
      end
    end

    def check_onboarding_status
      # Skip button bypasses onboarding check
      return if params[:skip] == 'true'

      # Allow re-onboarding if explicitly requested
      return if params[:review] == 'true'

      # Check if user has already completed this onboarding
      if current_user&.onboarding_completed?(@method)
        redirect_to_next_page
      end
    end

    def handle_eid_card_generation
      generation = params[:eid_card_generation].to_i

      if generation.between?(1, 5)
        # Store in user if logged in, otherwise in session
        if current_user
          current_user.update!(eid_card_generation: generation)
        else
          session[:eid_card_generation] = generation
        end

        # Move to next step
        redirect_to contract_onboarding_path(@contract, step: 'pin_check', method: @method, review: params[:review], recipient: @recipient&.uuid)
      else
        redirect_to contract_onboarding_path(@contract, step: 'eid_card_generation', method: @method, recipient: @recipient&.uuid),
                    alert: 'Please select your eID card generation'
      end
    end

    def handle_pin_check
      # User confirms they know their PIN
      redirect_to contract_onboarding_path(@contract, step: 'certificate_check', method: @method, review: params[:review], recipient: @recipient&.uuid)
    end

    def handle_certificate_check
      # User confirms they have certificates
      # Mark onboarding as complete
      if current_user
        current_user.mark_onboarding_complete!(@method)
      else
        session[:completed_onboardings] ||= []
        session[:completed_onboardings] << @method unless session[:completed_onboardings].include?(@method)
      end

      redirect_to_next_page
    end

    def handle_physical_instructions
      # Mark onboarding as complete
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
      when 'electronic'
        # Pass eid_card_generation to ensure it's available
        generation = current_user&.eid_card_generation || session[:eid_card_generation]
        redirect_to signature_apps_contract_path(@contract, recipient: @recipient&.uuid, eid_card_generation: generation)
      when 'physical'
        redirect_to physical_signing_contract_path(@contract, recipient: @recipient&.uuid)
      end
    end

    def first_step
      case @method
      when 'electronic'
        'eid_card_generation'
      when 'physical'
        'physical_instructions'
      end
    end
  end
end
