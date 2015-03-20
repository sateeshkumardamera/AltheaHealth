Rails.configuration.stripe = {
  :publishable_key => 'pk_test_M39vfbo9zpvg2G1ot1Y11ci1',
  :secret_key      => 'sk_test_nmd1wbf3YSi5uLEEqvAVhph9'
}

Stripe.api_key = Rails.configuration.stripe[:secret_key]