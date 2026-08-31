# frozen_string_literal: true

module Pushover
  class PermanentError < StandardError; end
  class TemporaryError < StandardError; end

  class Client
    VALIDATE_URL = 'https://api.pushover.net/1/users/validate.json'
    MESSAGES_URL = 'https://api.pushover.net/1/messages.json'
    NETWORK_ERRORS = [Timeout::Error, SocketError, SystemCallError, EOFError, Net::ProtocolError,
                      OpenSSL::SSL::SSLError].freeze

    def initialize(application_token:, recipient_key:)
      @application_token = application_token
      @recipient_key = recipient_key
    end

    def validate!
      post(VALIDATE_URL, token: @application_token, user: @recipient_key)
    end

    def deliver!(title:, message:, url: nil)
      body = { token: @application_token, user: @recipient_key, title: title, message: message }
      body[:url] = url if url

      post(MESSAGES_URL, body)
    end

    private

    def post(url, body)
      response = HTTParty.post(url, body: body, timeout: 10)
      payload = JSON.parse(response.body)
      error_class = response.code >= 500 ? TemporaryError : PermanentError

      raise error_class, error_message(response.code) unless payload.is_a?(Hash)

      if response.code >= 400 || payload['status'] != 1
        raise error_class, error_message(response.code, payload['request'])
      end

      true
    rescue JSON::ParserError
      error_class = response.code >= 500 ? TemporaryError : PermanentError
      raise error_class, error_message(response.code)
    rescue *NETWORK_ERRORS
      raise TemporaryError, 'Pushover request failed'
    end

    def error_message(status, request_id = nil)
      details = ["status #{status}", ("request #{request_id}" if request_id)].compact.join(', ')
      "Pushover request failed (#{details})"
    end
  end
end
