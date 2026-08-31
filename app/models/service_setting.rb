# frozen_string_literal: true

class ServiceSetting < ApplicationRecord
  belongs_to :user

  enum :service, { geocoding: 0, notifications: 1 }, prefix: :service

  encrypts :credentials

  validates :provider, presence: true
  validates :provider, uniqueness: { scope: %i[user_id service] }

  before_validation :normalize_by_schema
  validate :validate_by_schema

  def activate!
    user.with_lock do
      self.class.where(user_id: user_id, service: service).where.not(id: id).update_all(active: false)
      update!(active: true)
    end
  end

  def credentials_hash
    return {} if credentials.blank?

    JSON.parse(credentials)
  rescue JSON::ParserError, ActiveRecord::Encryption::Errors::Decryption
    {}
  end

  def api_key
    credentials_hash['api_key']
  end

  def api_key=(value)
    write_credential('api_key', value)
  end

  def application_token
    credentials_hash['application_token']
  end

  def application_token=(value)
    write_credential('application_token', value)
  end

  def recipient_key
    credentials_hash['recipient_key']
  end

  def recipient_key=(value)
    write_credential('recipient_key', value)
  end

  def host
    config['host']
  end

  def use_https
    config.fetch('use_https', true)
  end

  def rps
    config['rps']
  end

  def readable_credentials?
    credentials
    true
  rescue ActiveRecord::Encryption::Errors::Decryption
    false
  end

  def komoot?
    schema&.komoot? || false
  end

  def chibigeo?
    schema&.chibigeo? || false
  end

  def paid?
    schema&.paid? || false
  end

  private

  def schema
    if service_geocoding?
      ServiceSettings::GeocodingSchema.new(self)
    elsif service_notifications?
      ServiceSettings::NotificationsSchema.new(self)
    end
  end

  def write_credential(key, value)
    hash = credentials_hash
    if value.present?
      hash[key] = value.to_s.strip
    else
      hash.delete(key)
    end
    self.credentials = hash.empty? ? nil : hash.to_json
  end

  def normalize_by_schema
    schema&.normalize
  end

  def validate_by_schema
    schema&.validate
  end
end
