class PagesController < ApplicationController
  before_filter :check_init

  def index
    if @settings.default_campaign && ((user_signed_in? && current_user.admin?) || @settings.default_campaign.published_flag)
    	if current_user.present?
        redirect_to campaign_home_url(@settings.default_campaign, :sr=>current_user.sr)
      else
        
      	redirect_to campaign_home_url(@settings.default_campaign)
      end
    else
      @campaigns = Campaign.order("created_at ASC")
      render 'theme/views/homepage'
    end
  end
end
