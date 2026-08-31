# frozen_string_literal: true

class Families::ExpireLocationRequestsJob < ApplicationJob
  queue_as :families

  def perform
    Family::LocationRequest
      .pending
      .where('expires_at <= ?', Time.current)
      .find_each do |request|
        expired = request.with_lock do
          next false unless request.pending? && request.expires_at <= Time.current

          request.update!(status: :expired)
          true
        end

        next unless expired

        I18n.with_locale(request.requester.locale) do
          Families::Notify.new(
            user: request.requester,
            kind: :info,
            title: I18n.t('services.families.respond_to_location_request.expired_title'),
            content: I18n.t('services.families.respond_to_location_request.expired_content',
                            email: request.target_user.email)
          ).call
        end
      end
  end
end
