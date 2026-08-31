# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::Notify do
  subject(:notify) do
    described_class.new(user: user, kind: :warning, title: title, content: content, url: url).call
  end

  let(:user) { create(:user) }
  let(:title) { 'Family & Friends' }
  let(:content) { 'Location changed' }
  let(:url) { 'https://example.com/families' }

  it 'creates and returns an in-app notification without changing its localized arguments' do
    notification = nil

    I18n.with_locale(:fr) do
      expect { notification = notify }.to change(user.notifications, :count).by(1)
    end

    expect(notification).to have_attributes(
      user: user,
      kind: 'warning',
      title: title,
      content: content
    )
  end

  it 'enqueues Pushover delivery when the user has an active notification setting' do
    create(:service_setting, :pushover, :active, user: user)

    expect { notify }
      .to have_enqueued_job(Notifications::PushoverDeliveryJob)
      .with(instance_of(Integer), url)
  end

  it 'does not enqueue Pushover delivery without a setting' do
    expect { notify }.not_to have_enqueued_job(Notifications::PushoverDeliveryJob)
  end

  it 'does not enqueue Pushover delivery when the setting is disabled' do
    create(:service_setting, :pushover, user: user)

    expect { notify }.not_to have_enqueued_job(Notifications::PushoverDeliveryJob)
  end

  it 'reports creation failures with the user ID and returns nil' do
    error = ActiveRecord::RecordInvalid.new(Notification.new)
    allow(Notification).to receive(:create!).and_raise(error)
    allow(ExceptionReporter).to receive(:call)

    expect(notify).to be_nil
    expect(ExceptionReporter).to have_received(:call).with(error, include(user.id.to_s))
  end
end
