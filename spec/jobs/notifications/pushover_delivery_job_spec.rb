# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::PushoverDeliveryJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { create(:user) }
  let!(:setting) { create(:service_setting, :pushover, :active, user: user) }
  let(:notification) do
    create(
      :notification,
      user: user,
      title: '<b>Family &amp; Friends</b>',
      content: "<p>Location&nbsp; changed</p>\n<div>Open the map</div>"
    )
  end
  let(:url) { 'https://example.com/families' }
  let(:client) { instance_double(Pushover::Client, deliver!: true) }

  before do
    allow(Pushover::Client).to receive(:new).and_return(client)
  end

  it 'uses the families queue and handles the expected delivery errors' do
    expect(described_class.queue_name).to eq('families')
    expect(described_class.rescue_handlers.map(&:first)).to include(
      'Pushover::TemporaryError',
      'Pushover::PermanentError',
      'ActiveRecord::RecordNotFound'
    )
  end

  it 'reloads credentials and delivers sanitized plain text with the optional URL' do
    described_class.perform_now(notification.id, url)

    expect(Pushover::Client).to have_received(:new).with(
      application_token: setting.application_token,
      recipient_key: setting.recipient_key
    )
    expect(client).to have_received(:deliver!).with(
      title: 'Family & Friends',
      message: 'Location changed Open the map',
      url: url
    )
  end

  it 'uses current notification data and truncates Pushover title and message limits' do
    notification.update_columns(title: "<b>#{'T' * 260}</b>", content: "<p>#{'M' * 1_030}</p>")

    described_class.perform_now(notification.id)

    expect(client).to have_received(:deliver!).with(
      title: 'T' * 250,
      message: 'M' * 1_024,
      url: nil
    )
  end

  it 'does not deliver when the setting has been removed' do
    notification
    setting.destroy!

    described_class.perform_now(notification.id, url)

    expect(Pushover::Client).not_to have_received(:new)
  end

  it 'does not deliver when the setting has been disabled' do
    notification
    setting.update!(active: false)

    described_class.perform_now(notification.id, url)

    expect(Pushover::Client).not_to have_received(:new)
  end

  it 'retries temporary failures after five seconds' do
    allow(client).to receive(:deliver!).and_raise(Pushover::TemporaryError)

    travel_to(Time.current) do
      expect { described_class.perform_now(notification.id, url) }
        .to have_enqueued_job(described_class)
        .with(notification.id, url)
        .at(be_within(1.second).of(5.seconds.from_now))
    end
  end

  it 'discards permanent failures' do
    allow(client).to receive(:deliver!).and_raise(Pushover::PermanentError)

    expect { described_class.perform_now(notification.id, url) }.not_to raise_error
  end

  it 'discards missing notifications' do
    expect { described_class.perform_now(-1, url) }.not_to raise_error
  end
end
