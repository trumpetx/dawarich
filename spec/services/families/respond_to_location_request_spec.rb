# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::RespondToLocationRequest do
  let(:family) { create(:family) }
  let(:requester) { create(:user) }
  let(:target) { create(:user) }
  let!(:requester_membership) { create(:family_membership, user: requester, family: family, role: :owner) }
  let!(:target_membership) { create(:family_membership, user: target, family: family, role: :member) }
  let(:request) { create(:family_location_request, requester: requester, target_user: target, family: family) }

  describe '#call' do
    it 'accepts a request, enables sharing with the given duration' do
      result = described_class.new(request: request, responder: target, decision: :accept, duration: '1h').call

      expect(result.success?).to be true
      expect(request.reload).to be_accepted
      expect(request.responded_at).to be_present
      expect(target.reload.family_sharing_enabled?).to be true
      expect(target.family_sharing_duration).to eq('1h')
    end

    it 'notifies the requester in their locale when accepted' do
      requester.update!(settings: { 'locale' => 'fr' })

      expect do
        described_class.new(request: request, responder: target, decision: :accept).call
      end.to change { Notification.where(user: requester).count }.by(1)

      notification = Notification.where(user: requester).last
      expect(notification.title).to eq('Demande de localisation acceptée')
      expect(notification.content).to eq("#{target.email} a accepté votre demande de localisation.")
    end

    it 'includes the configured Family URL in accepted notifications' do
      notifier = instance_double(Families::Notify, call: nil)
      allow(Families::Notify).to receive(:new).and_return(notifier)

      described_class.new(request: request, responder: target, decision: :accept).call

      expect(Families::Notify).to have_received(:new).with(
        user: requester,
        kind: :info,
        title: I18n.t('services.families.respond_to_location_request.accepted_title'),
        content: I18n.t('services.families.respond_to_location_request.accepted_content', email: target.email),
        url: Rails.application.routes.url_helpers.family_url(**ActionMailer::Base.default_url_options)
      )
      expect(notifier).to have_received(:call)
    end

    it 'falls back to the suggested duration on accept' do
      described_class.new(request: request, responder: target, decision: :accept).call

      expect(target.reload.family_sharing_duration).to eq(request.suggested_duration)
    end

    it 'declines a request without enabling sharing' do
      result = described_class.new(request: request, responder: target, decision: :decline).call

      expect(result.success?).to be true
      expect(request.reload).to be_declined
      expect(target.reload.family_sharing_enabled?).to be false
    end

    it 'notifies the requester in their locale when declined' do
      requester.update!(settings: { 'locale' => 'fr' })

      expect do
        described_class.new(request: request, responder: target, decision: :decline).call
      end.to change { Notification.where(user: requester).count }.by(1)

      notification = Notification.where(user: requester).last
      expect(notification.title).to eq('Demande de localisation refusée')
      expect(notification.content).to eq("#{target.email} a refusé votre demande de localisation.")
    end

    it 'rejects a responder who is not the target' do
      result = nil

      expect do
        result = described_class.new(request: request, responder: requester, decision: :accept).call
      end.not_to change(Notification, :count)

      expect(result.success?).to be false
      expect(result.status).to eq(:forbidden)
    end

    it 'rejects an expired request' do
      request.update!(expires_at: 1.hour.ago)

      result = nil

      expect do
        result = described_class.new(request: request, responder: target, decision: :accept).call
      end.not_to change(Notification, :count)

      expect(result.success?).to be false
      expect(result.status).to eq(:unprocessable_content)
    end
  end
end
