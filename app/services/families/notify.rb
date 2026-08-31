# frozen_string_literal: true

module Families
  class Notify
    def initialize(user:, kind:, title:, content:, url: nil)
      @user = user
      @kind = kind
      @title = title
      @content = content
      @url = url
    end

    def call
      notification = Notification.create!(user: user, kind: kind, title: title, content: content)

      if user.service_settings.service_notifications.exists?(provider: 'pushover', active: true)
        Notifications::PushoverDeliveryJob.perform_later(notification.id, url)
      end

      notification
    rescue StandardError => e
      ExceptionReporter.call(e, "Failed to notify user #{user.id} of Family event")
      nil
    end

    private

    attr_reader :user, :kind, :title, :content, :url
  end
end
