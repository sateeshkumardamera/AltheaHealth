class CampaignsController < ApplicationController
  include CheckoutMixin

  layout 'layouts/checkout'
  before_filter :check_init
  before_filter :load_campaign
  before_filter :check_published
  before_filter :check_exp, :except => [:home, :checkout_confirmation]

  # The load_campaign before filter grabs the campaign object from the db
  # and makes it available to all routes

  def home
    render 'theme/views/campaign', layout: 'layouts/application'
  end

  def checkout_amount
    @changePageTitle = true
    if !(@campaign.facebook_description.nil? or @campaign.facebook_description == '')
      @amountArray = @campaign.facebook_description.split(',')
    end
    @reward = false
    if params.has_key?(:reward) && params[:reward].to_i != 0
      @reward = Reward.find_by_id(params[:reward])
      unless @reward && @reward.campaign_id == @campaign.id && !@reward.sold_out?
        @reward = false
        flash.now[:info] = "This reward is unavailable. Please select a different reward!"
      end
    end
  end

  def checkout_payment
    @changePageTitle = true
    @reward = false
    params[:amount].sub!(',', '') if params[:amount].present?
    params[:amount_other].sub!(',', '') if params[:amount_other].present?
    params[:quantity].sub!(',', '') if params[:quantity].present?
    @amount = params[:amount_other] if params[:amount_other].present?
    logger.info "ALTHEA AMOUNT IS*************#{params[:quantity]}"
    if @campaign.payment_type == "fixed"
      if (params.has_key?(:quantity) && params[:quantity].to_i != 1)
        @quantity = params[:quantity].to_i
        #@amount = ((@quantity * @campaign.fixed_payment_amount.to_f)*100).ceil/100.0
        @amount = (@quantity*100).ceil/100.0
        logger.info "ALTHEA @quantity IS*************#{@quantity}"
        logger.info "ALTHEA @amount IS*************#{@amount}"
      elsif (params.has_key?(:quantity) && params[:quantity].to_i == 1 && params.has_key?(:amount_other) && params[:amount_other].to_i > 0)
        if params[:amount_other].to_i > 0
          @amount = (params[:amount_other].to_i*100).ceil/100.0
          #if params[:amount_other].to_f < @campaign.fixed_payment_amount  
           # redirect_to checkout_amount_url(@campaign), flash: { warning: "Minimum donation is $#{@campaign.fixed_payment_amount.to_i}"}
          #end
          if params[:amount_other].to_f < 5  
            #redirect_to checkout_amount_url(@campaign), flash: { warning: "Minimum donation is $#{@campaign.fixed_payment_amount.to_i}"}
            redirect_to checkout_amount_url(@campaign), flash: { warning: "Minimum donation is $5"}
          end 
        else
        redirect_to checkout_amount_url(@campaign), flash: { warning: "Please choose a valid amount!" }
        end
        
      else
        redirect_to checkout_amount_url(@campaign), flash: { warning: "Please choose a valid amount!" }
        return
      end
    elsif params.has_key?(:amount) && params[:amount].to_f >= @campaign.min_payment_amount
      @amount = ((params[:amount].to_f)*100).ceil/100.0
      @quantity = 1
      if params.has_key?(:reward) && params[:reward].to_i != 0
        begin
          @reward = Reward.find(params[:reward])
        rescue StandardError => exception
          redirect_to checkout_amount_url(@campaign), flash: { info: "This reward is unavailable. Please select a different reward!" }
          return
        end
        unless @reward && @reward.campaign_id == @campaign.id && @amount >= @reward.price && !@reward.sold_out?
          if @reward.sold_out?
            flash = { info: "This reward is unavailable. Please select a different reward!" }
          else
            flash = { warning: "Please enter a higher amount to redeem this reward!" }
          end
          redirect_to checkout_amount_url(@campaign), flash: flash and return
        end
      end

    else
      redirect_to checkout_amount_url(@campaign), flash: { info: "Please enter a higher amount!" }
      return
    end

    @fee = (@campaign.apply_processing_fee)? calculate_processing_fee(@amount * 100)/100.0 : 0
    @total = @amount + @fee

  end


  def checkout_process
    payment_params = basic_payment_info(params)

    ct_user_id = params[:ct_user_id]
    ct_card_id = params[:ct_card_id]
    sr = params[:sr]

    # calculate amount and fee in cents
    fee = calculate_processing_fee(payment_params[:amount])

    @reward = false
    if params[:reward].to_i != 0
      @reward = Reward.find_by_id(params[:reward])
      unless reward_choice_validates?(@reward, @campaign, payment_params[:amount])
        if @reward.sold_out?
          flash = { info: "This reward is unavailable. Please select a different reward!" }
        else
          flash = { warning: "Please enter a higher amount to redeem this reward!" }
        end
        redirect_to checkout_amount_url(@campaign, :sr => params[:sr]), flash: flash and return
      end
    end

    # Apply the processing fee to the user or the admin
    if @campaign.apply_processing_fee
      user_fee_amount = fee
      admin_fee_amount = 0
    else
      user_fee_amount = 0
      admin_fee_amount = fee
    end

    # TODO: Check to make sure the amount is valid here
    # Create the payment record in our db, if there are errors, redirect the user
    @payment = @campaign.payments.new(payment_params)
    

    unless @payment.valid?
      error_messages = @payment.errors.full_messages.join(', ')
      redirect_to checkout_amount_url(@campaign), flash: { error: error_messages } and return
    end
    
    # Check if there's an existing sr value in the payment which has been from url params.
    # if there is no sr then assigning sr which is there in cookie 
    if @payment.sponsor_reference == ''
      logger.info "ALTHEA SPONSOR REFERENCE CODE IS*************#{cookies[:alt_sr]}"
      @payment.sponsor_reference = cookies[:alt_sr]
    end

    # Check if there's an existing payment with the same payment_params and client_timestamp. 
    # If exists, look at the status to route accordingly. 
    if !payment_params[:client_timestamp].nil? && (existing_payment = @campaign.payments.where(payment_params).first)
      case existing_payment.status
      when nil
        flash_msg = { info: "Your payment is still being processed! If you have not received a confirmation email, please try again or contact support by emailing support@altheahealth.com" }
      when 'error'
        flash_msg = { error: "There was an error processing your payment. Please try again or contact support by emailing support@altheahealth.com." }
      else
        # A status other than nil or 'error' indicates success! Treat as original payment
        redirect_to checkout_confirmation_url(@campaign, :sr => params[:sr]), :status => 303, :flash => { payment_guid: @payment.ct_payment_id } and return
      end
      redirect_to checkout_amount_url(@campaign, :sr => params[:sr]), flash: flash_msg and return
    end

    @payment.reward = @reward if @reward
    @payment.status = 'pending'
    @payment.save

    payment = {
        :amount          => payment_params[:amount],
        :currency        => "usd",
        :source          => params[:stripeToken],
        :description     => payment_params[:email],
        :receipt_email   => payment_params[:email],
        # :application_fee => user_fee_amount,
        
        metadata: {
          fullname: payment_params[:fullname],
          email: payment_params[:email],
          billing_postal_code: payment_params[:billing_postal_code],
          quantity: payment_params[:quantity],
          reward: @reward ? @reward.id : 0,
          additional_info: payment_params[:additional_info]
        }
      }
      
    ## Handling Exception for Stripe - Code added by Ravi
    begin
      response = Stripe::Charge.create(payment)
      ravi_str =  JSON.pretty_generate(response)
      
      logger.info "Sending Payment Object #{payment}"
      logger.info "Got the response Json #{ravi_str}"

    rescue Stripe::CardError => e
      logger.error "Sending Payment Object #{payment}"
      logger.error "Got the response Json #{ravi_str}"
      logger.error "SUPPORT_ERROR There was an error processing your payment. #{e.message}"
      logger.info "::1"
      redirect_to checkout_amount_url(@campaign, :sr => params[:sr]), flash: { error: "There was an error processing your payment. " } and return
    rescue Stripe::InvalidRequestError => e
      logger.error "Sending Payment Object #{payment}"
      logger.error "Got the response Json #{ravi_str}"
      logger.error "SUPPORT_ERROR There was an error processing your payment. #{e.message}"
      logger.info "::2"
      redirect_to checkout_amount_url(@campaign, :sr => params[:sr]), flash: { error: "There was an unexpected error processing your payment. Support has been notified. Please try again later. " } and return
    rescue Stripe::AuthenticationError => e
      logger.error "Sending Payment Object #{payment}"
      logger.error "Got the response Json #{ravi_str}"
      logger.error "SUPPORT_ERROR There was an error processing your payment. #{e.message}"
      logger.info "::3"
      redirect_to checkout_amount_url(@campaign, :sr => params[:sr]), flash: { error: "There was an unexpected error processing your payment. Support has been notified. Please try again later. " } and return
    rescue Stripe::APIConnectionError => e
      logger.error "Sending Payment Object #{payment}"
      logger.error "Got the response Json #{ravi_str}"
      logger.error "SUPPORT_ERROR There was an error processing your payment. #{e.message}"
      logger.info "::4"
      redirect_to checkout_amount_url(@campaign, :sr => params[:sr]), flash: { error: "There was an unexpected error processing your payment. Support has been notified. Please try again later. " } and return
    rescue Stripe::StripeError => e
      logger.error "Sending Payment Object #{payment}"
      logger.error "Got the response Json #{ravi_str}"
      logger.error "SUPPORT_ERROR There was an error processing your payment. #{e.message}"
      logger.info "::5"
      redirect_to checkout_amount_url(@campaign, :sr => params[:sr]), flash: { error: "There was an unexpected error processing your payment. Support has been notified. Please try again later." } and return
    rescue StandardError => e
      logger.error "Sending Payment Object #{payment}"
      logger.error "Got the response Json #{ravi_str}"
      logger.error "SUPPORT_ERROR There was an error processing your payment. #{e.message}"
      logger.info "::6"
      redirect_to checkout_amount_url(@campaign, :sr => params[:sr]), flash: { error: "There was an unexpected error processing your payment. Support has been notified. Please try again later." } and return
    rescue => e
      logger.error "Sending Payment Object #{payment}"
      logger.error "Got the response Json #{ravi_str}"
      logger.error "SUPPORT_ERROR There was an error processing your payment. #{e.message}"
      logger.info "::7"
      redirect_to checkout_amount_url(@campaign, :sr => params[:sr]), flash: { error: "There was an unexpected error processing your payment. Support has been notified. Please try again later." } and return
    end

    ## begin
    ## response = Stripe::Charge.create(payment)
    ## rescue Stripe::CardError => e
    ##  response.status = 'error'
    ##  redirect_to checkout_amount_url(@campaign, :sr => params[:sr]), flash: { error: "There was an error processing your payment. #{e.message}" } and return
    ## end

    ## The below code is of no use - RAVI
    ## if response.status != 'succeeded'
    ##  response.status = 'error'
    ##  redirect_to checkout_amount_url(@campaign, :sr => params[:sr]), flash: { error: "There was an error processing your payment." } and return
    ## else
    ##  response.status = 'charged'
    ## end
    
    result = { response: response, payment: payment.merge!({ user_fee_amount: user_fee_amount, admin_fee_amount: admin_fee_amount }) }
    
    # Sync payment data
    @payment.update_api_data(result)
    @payment.ct_charge_request_id = response.id
    @payment.save

    redirect_to checkout_confirmation_url(@campaign, :sr => params[:sr]), :status => 303, :flash => { payment_guid: @payment.ct_payment_id } and return
  end

  def checkout_confirmation
    @disable_nav = true
    @changePageTitle = true
    @payment = Payment.where(:ct_payment_id => flash[:payment_guid]).first
    flash.keep(:payment_guid) # Preserve on refresh of this page only

    if flash[:payment_guid].nil? || !@payment
      redirect_to campaign_home_url(@campaign)
    end
  end

  def checkout_error
    payment_info = basic_payment_info(params)
    payment_info[:ct_tokenize_request_error_id] = params[:ct_tokenize_request_error_id]
    payment_info[:status] = 'error'
    payment = @campaign.payments.new(payment_info)
    payment.save

    render nothing: true
  end

  def ajax_create_payment_user
    @campaign.production_flag? ? Crowdtilt.production(@settings) : Crowdtilt.sandbox
    begin
      render text: Crowdtilt.create_user(email: params[:email])['id']
    rescue
      render text: 'error', status: 400
    end
  end

  private

  def load_campaign
    @campaign = Campaign.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to root_url
  end

  def check_published
    if !@campaign.published_flag
      unless user_signed_in? && current_user.admin?
        redirect_to root_url, :flash => { :info => "Campaign is no longer available" }
      end
    end
  end

  def check_exp
    if @campaign.expired?
      redirect_to campaign_home_url(@campaign), :info => { :error => "Campaign is expired!" }
    end
  end

end
