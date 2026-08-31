# frozen_string_literal: true

require_dependency 'pushover/client'

module Notifications
  class PushoverDeliveryJob < ApplicationJob
    queue_as :families

    retry_on Pushover::TemporaryError, wait: 5.seconds, attempts: 3
    discard_on Pushover::PermanentError, ActiveRecord::RecordNotFound

    def perform(notification_id, url = nil)
      notification = Notification.find(notification_id)
      setting = notification.user.service_settings.service_notifications.find_by(provider: 'pushover', active: true)
      return unless setting

      sanitizer = ActionView::Base.full_sanitizer
      title = Nokogiri::HTML.fragment(sanitizer.sanitize(notification.title)).text.squish.truncate(250, omission: '')
      message = Nokogiri::HTML.fragment(sanitizer.sanitize(notification.content))
                              .text.squish.truncate(1_024, omission: '')

      Pushover::Client.new(
        application_token: setting.application_token,
        recipient_key: setting.recipient_key
      ).deliver!(title: title, message: message, url: url)
    end
  end
end
