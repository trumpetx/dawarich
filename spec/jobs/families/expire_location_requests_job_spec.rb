# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::ExpireLocationRequestsJob, type: :job do
  let(:family) { create(:family) }
  let(:requester) { family.creator }
  let(:target_user) { create(:user) }

  before do
    create(:family_membership, family: family, user: requester, role: :owner)
    create(:family_membership, family: family, user: target_user)
  end

  describe '#perform' do
    it 'expires pending requests past their expires_at' do
      expired = create(:family_location_request,
                       requester: requester, target_user: target_user, family: family,
                       status: :pending, expires_at: 1.hour.ago)

      described_class.perform_now

      expect(expired.reload).to be_expired
    end

    it 'notifies each requester in their locale when their request expires' do
      requester.update!(settings: { 'locale' => 'fr' })
      other_family = create(:family)
      other_requester = other_family.creator
      other_target = create(:user)
      create(:family_membership, family: other_family, user: other_requester, role: :owner)
      create(:family_membership, family: other_family, user: other_target)
      create(:family_location_request, requester: requester, target_user: target_user, family: family,
                                       status: :pending, expires_at: 1.hour.ago)
      create(:family_location_request, requester: other_requester, target_user: other_target, family: other_family,
                                       status: :pending, expires_at: 1.hour.ago)

      expect { described_class.perform_now }.to change(Notification, :count).by(2)

      notification = Notification.where(user: requester).last
      expect(notification.title).to eq('Demande de localisation expirée')
      expect(notification.content).to eq("Votre demande de localisation à #{target_user.email} a expiré.")
      expect(Notification.where(user: other_requester).count).to eq(1)
    end

    it 'does not expire pending requests still within their window' do
      active = create(:family_location_request,
                      requester: requester, target_user: target_user, family: family,
                      status: :pending, expires_at: 1.hour.from_now)

      expect { described_class.perform_now }.not_to change(Notification, :count)

      expect(active.reload).to be_pending
    end

    it 'does not change already accepted requests' do
      accepted = create(:family_location_request,
                        requester: requester, target_user: target_user, family: family,
                        status: :accepted, expires_at: 1.hour.ago)

      expect { described_class.perform_now }.not_to change(Notification, :count)

      expect(accepted.reload).to be_accepted
    end

    it 'does not change already declined requests' do
      declined = create(:family_location_request,
                        requester: requester, target_user: target_user, family: family,
                        status: :declined, expires_at: 1.hour.ago)

      expect { described_class.perform_now }.not_to change(Notification, :count)

      expect(declined.reload).to be_declined
    end

    it 'writes correct integer enum value for expired status' do
      expired = create(:family_location_request,
                       requester: requester, target_user: target_user, family: family,
                       status: :pending, expires_at: 1.hour.ago)

      described_class.perform_now

      raw_status = Family::LocationRequest.where(id: expired.id).pick(:status)
      expect(raw_status).to eq('expired')
    end

    it 'is idempotent' do
      expired = create(:family_location_request,
                       requester: requester, target_user: target_user, family: family,
                       status: :pending, expires_at: 1.hour.ago)

      described_class.perform_now

      expect { described_class.perform_now }.not_to change(Notification, :count)

      expect(expired.reload).to be_expired
      expect(Notification.where(user: requester).count).to eq(1)
    end
  end
end
