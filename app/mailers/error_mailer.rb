class ErrorMailer < ActionMailer::Base
  layout 'default_mailer'
  default from: "Althea Social Funds <#{ENV['MAILGUN_USERNAME']}>"

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
        subject: "Error while making payment for the campaign: \"#{@campaign.name}\""
      )
    end
  end

end
