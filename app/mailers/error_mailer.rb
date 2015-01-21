class ErrorMailer < ActionMailer::Base
  layout 'default_mailer'
  default from: "me@sandbox2aa0585151424332bfa819edb0dc9b13.mailgun.org"

  helper :campaigns

  def error_notification(campaign, payment)
    recipients = User
      .where(admin: true, wants_admin_payment_notification: true)
      .all
      .map { |user| user.email }
    if (recipients.length > 0)
      @settings = Settings.first
      @campaign = campaign
      @payment = payment
      mail(
        to: "support@altheahealth.com",
        cc: recipients,
        subject: "Error while making paymnet for the campaign: \"#{@campaign.name}\""
      )
    end
  end

end
