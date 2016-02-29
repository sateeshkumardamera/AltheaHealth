class FeedbackMailer < ActionMailer::Base
  layout 'default_mailer'
  default from: "Althea Social Funds <#{ENV['MAILGUN_USERNAME']}>"

  helper :campaigns

  def feedback_notification(campaign)
    recipients = User
      .where(admin: true, wants_admin_payment_notification: true)
      .all
      .map { |user| user.email }
    if (recipients.length > 0)
      @settings = Settings.first
      @campaign = campaign
      mail(
        to: "#{ENV['SUPPORT_EMAIL']}",
        cc: recipients,
        subject: "Feedback from a Donor for the campaign: \"#{@campaign.name}\""
      )
    end
  end

end
