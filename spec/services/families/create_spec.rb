# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::Create do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user: user, name: 'Test Family') }

  describe '#call' do
    context 'when user is not in a family' do
      it 'creates a family successfully' do
        expect { service.call }.to change(Family, :count).by(1)
        expect(service.family.name).to eq('Test Family')
        expect(service.family.creator).to eq(user)
      end

      it 'creates owner membership' do
        service.call
        membership = user.reload.family_membership
        expect(membership.role).to eq('owner')
        expect(membership.family).to eq(service.family)
      end

      it 'returns true on success' do
        expect(service.call).to be true
      end

      it 'routes the notification through Families::Notify in the user locale' do
        user.update!(settings: { 'locale' => 'fr' })
        notifier = instance_double(Families::Notify, call: nil)
        allow(Families::Notify).to receive(:new).and_return(notifier)

        service.call

        expect(Families::Notify).to have_received(:new).with(
          user: user,
          kind: :info,
          title: I18n.t('services.families.create.family_created', locale: :fr),
          content: I18n.t('services.families.create.you_ve_successfully_created_the_family_name',
                          name: 'Test Family', locale: :fr)
        )
        expect(notifier).to have_received(:call)
      end
    end

    context 'when user is already in a family' do
      before { create(:family_membership, user: user) }

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create a family' do
        expect { service.call }.not_to change(Family, :count)
      end

      it 'does not create a membership' do
        expect { service.call }.not_to change(Family::Membership, :count)
      end

      it 'sets appropriate error message' do
        service.call
        expect(service.error_message).to eq('You must leave your current family before creating a new one')
      end
    end

    context 'when user has already created a family before' do
      before do
        # User creates and then deletes their family membership, but family still exists
        old_family = create(:family, creator: user)
        membership = create(:family_membership, user: user, family: old_family, role: :owner)
        membership.destroy! # User leaves the family but family still exists
        user.reload # Ensure user association is refreshed
      end

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create a family' do
        expect { service.call }.not_to change(Family, :count)
      end

      it 'does not create a membership' do
        expect { service.call }.not_to change(Family::Membership, :count)
      end

      it 'sets appropriate error message' do
        service.call
        expect(service.error_message).to eq('You have already created a family. Each user can only create one family')
      end
    end

    context 'when cloud and the user is not on the family plan' do
      let(:user) { create(:user, plan: :pro, skip_auto_trial: true) }

      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'returns false and does not create a family' do
        expect(service.call).to be false
        expect { service.call }.not_to change(Family, :count)
        expect(service.error_message).to eq('Family feature requires an active subscription')
      end
    end

    context 'when cloud and the user is on the family plan' do
      let(:user) { create(:user, plan: :family, skip_auto_trial: true) }

      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'creates a family' do
        expect { service.call }.to change(Family, :count).by(1)
      end
    end
  end
end
