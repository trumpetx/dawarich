# frozen_string_literal: true

class Settings::PushoverController < ApplicationController
  FLASH_MESSAGE_BYTES = 512

  before_action :authenticate_user!
  before_action :authenticate_active_user!
  before_action :require_family_feature!

  def update
    return clear_setting if pushover_params[:clear] == '1'

    setting = current_user.service_settings.service_notifications.find_or_initialize_by(provider: 'pushover')
    setting.application_token = pushover_params[:application_token] if pushover_params[:application_token].present?
    setting.recipient_key = pushover_params[:recipient_key] if pushover_params[:recipient_key].present?
    enabled = ActiveModel::Type::Boolean.new.cast(pushover_params[:enabled])

    if !setting.valid?
      flash[:alert] = flash_message(setting.errors.full_messages.to_sentence)
    else
      setting.active = enabled
      setting.save!
      enabled ? validate_setting(setting) : flash[:notice] = t('.disabled')
    end

    redirect_to settings_integrations_path(service: 'pushover'), status: :see_other
  end

  private

  def pushover_params
    params.require(:pushover).permit(:application_token, :recipient_key, :enabled, :clear)
  end

  def clear_setting
    current_user.service_settings.service_notifications.where(provider: 'pushover').destroy_all
    flash[:notice] = t('.cleared')
    redirect_to settings_integrations_path(service: 'pushover'), status: :see_other
  end

  # The client's error messages carry only the HTTP status and Pushover request
  # id, never response bodies or credentials, so they are safe to show once
  # bounded to the flash cookie limit.
  def validate_setting(setting)
    Pushover::Client.new(
      application_token: setting.application_token,
      recipient_key: setting.recipient_key
    ).validate!
    record_connection_status(setting, 'ok')
    flash[:notice] = t('.verified')
  rescue Pushover::PermanentError, Pushover::TemporaryError => e
    record_connection_status(setting, 'failed')
    flash[:alert] = flash_message(e.message)
  end

  def record_connection_status(setting, status)
    setting.config['connection_status'] = status
    setting.update_column(:config, setting.config)
  end

  def flash_message(message)
    message.to_s.truncate_bytes(FLASH_MESSAGE_BYTES)
  end

  def require_family_feature!
    return if DawarichSettings.family_feature_available_for?(current_user)

    redirect_to settings_integrations_path, alert: t('.unavailable'), status: :see_other
  end
end
