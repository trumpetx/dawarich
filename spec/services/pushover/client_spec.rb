# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pushover::Client do
  subject(:client) { described_class.new(application_token: token, recipient_key: recipient_key) }

  let(:token) { 'application-secret' }
  let(:recipient_key) { 'recipient-secret' }
  let(:validate_url) { 'https://api.pushover.net/1/users/validate.json' }
  let(:messages_url) { 'https://api.pushover.net/1/messages.json' }

  describe '#validate!' do
    it 'posts form-encoded credentials with a 10-second timeout' do
      request = stub_request(:post, validate_url)
                .with(
                  body: { 'token' => token, 'user' => recipient_key },
                  headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }
                )
                .to_return(status: 200, body: { status: 1, request: 'request-id' }.to_json)

      expect(HTTParty).to receive(:post)
        .with(validate_url, hash_including(timeout: 10))
        .and_call_original

      expect(client.validate!).to be(true)
      expect(request).to have_been_requested
    end
  end

  describe '#deliver!' do
    it 'posts a form-encoded message without an omitted URL' do
      request = stub_request(:post, messages_url)
                .with do |request|
                  form = CGI.parse(request.body).transform_values(&:first)
                  request.headers['Content-Type'] == 'application/x-www-form-urlencoded' && form == {
                    'token' => token,
                    'user' => recipient_key,
                    'title' => 'Title',
                    'message' => 'Body'
                  }
                end
                .to_return(status: 200, body: { status: 1, request: 'request-id' }.to_json)

      expect(client.deliver!(title: 'Title', message: 'Body')).to be(true)
      expect(request).to have_been_requested
    end

    it 'includes a supplied URL' do
      request = stub_request(:post, messages_url)
                .with(body: hash_including('url' => 'https://example.com/visit'))
                .to_return(status: 200, body: { status: 1, request: 'request-id' }.to_json)

      expect(client.deliver!(title: 'Title', message: 'Body', url: 'https://example.com/visit')).to be(true)
      expect(request).to have_been_requested
    end
  end

  describe 'failures' do
    it 'raises a permanent error for client responses without exposing secrets or the body' do
      [401, 429].each do |status|
        stub_request(:post, validate_url)
          .to_return(status: status, body: { status: 0, request: 'request-id', errors: ['sensitive body'] }.to_json)

        expect { client.validate! }
          .to raise_error(Pushover::PermanentError, "Pushover request failed (status #{status}, request request-id)")
      end
    end

    it 'raises a permanent error when the API reports failure' do
      stub_request(:post, validate_url)
        .to_return(status: 200, body: { status: 0, request: 'request-id', errors: ['invalid credentials'] }.to_json)

      expect { client.validate! }
        .to raise_error(Pushover::PermanentError, 'Pushover request failed (status 200, request request-id)')
    end

    it 'raises a permanent error for invalid JSON without exposing the body' do
      stub_request(:post, validate_url).to_return(status: 200, body: 'sensitive invalid JSON')

      expect { client.validate! }
        .to raise_error(Pushover::PermanentError, 'Pushover request failed (status 200)')
    end

    ['null', '[]'].each do |body|
      it "raises a permanent error for the valid non-object JSON #{body}" do
        stub_request(:post, validate_url).to_return(status: 200, body: body)

        expect { client.validate! }
          .to raise_error(Pushover::PermanentError, 'Pushover request failed (status 200)')
      end
    end

    it 'raises a temporary error for server responses' do
      stub_request(:post, validate_url)
        .to_return(status: 500, body: { status: 0, request: 'request-id', errors: ['sensitive body'] }.to_json)

      expect { client.validate! }
        .to raise_error(Pushover::TemporaryError, 'Pushover request failed (status 500, request request-id)')
    end

    [
      Net::OpenTimeout.new('application-secret'),
      Net::ReadTimeout.new('recipient-secret'),
      Timeout::Error.new('application-secret'),
      SocketError.new('recipient-secret'),
      Errno::ECONNREFUSED.new,
      Errno::ECONNRESET.new,
      Errno::EPIPE.new,
      EOFError.new('application-secret'),
      OpenSSL::SSL::SSLError.new('recipient-secret')
    ].each do |error|
      it "raises a temporary error for #{error.class}" do
        stub_request(:post, validate_url).to_raise(error)

        expect { client.validate! }
          .to raise_error(Pushover::TemporaryError, 'Pushover request failed')
      end
    end

    it 'raises a temporary error for protocol errors without exposing their message' do
      stub_request(:post, validate_url).to_raise(Net::ProtocolError.new('application-secret'))

      expect { client.validate! }
        .to raise_error(Pushover::TemporaryError, 'Pushover request failed')
    end
  end
end
