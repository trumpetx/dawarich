# frozen_string_literal: true

module ServiceSettings
  class NotificationsSchema
    CREDENTIAL_FORMAT = /\A[A-Za-z0-9]{30}\z/

    def initialize(setting)
      @setting = setting
    end

    def normalize; end

    def validate
      setting.errors.add(:provider, :inclusion) unless setting.provider == 'pushover'
      setting.errors.add(:application_token, :invalid) unless setting.application_token&.match?(CREDENTIAL_FORMAT)
      setting.errors.add(:recipient_key, :invalid) unless setting.recipient_key&.match?(CREDENTIAL_FORMAT)
    end

    private

    attr_reader :setting
  end
end
