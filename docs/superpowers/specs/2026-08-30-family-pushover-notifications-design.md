# Family Pushover Notifications Design

## Context

Dawarich already stores in-app notifications, broadcasts them through Turbo,
and emails selected Family events. Family location sharing also has web and
mobile APIs, but Dawarich has no external push delivery, device registration,
or safety/freshness alerts.

The first contribution will deliver Family notifications through Pushover.
It will establish one Family-domain notification entry point that later
stale-location and low-battery evaluators can reuse without depending on
Pushover directly.

## Goals

- Preserve existing in-app Family notifications and Turbo behavior.
- Deliver Family notifications to Pushover asynchronously when configured.
- Store each user's Pushover application token and user/group key encrypted.
- Add notifications for location requests that are accepted, declined, or
  expire.
- Support cloud and self-hosted users wherever the Family feature is available.
- Leave a small, provider-independent entry point for future Family alerts.

## Non-goals

- Stale-location, low-battery, geofence, or emergency-priority alerts.
- APNs, FCM, browser push, or changes to mobile applications.
- A generic notification-provider framework or webhook system.
- Notification category preferences or delivery-history persistence.
- Retrofitting non-Family Dawarich notifications for Pushover delivery.

## Architecture

`Families::Notify` is the single Family-domain entry point. It accepts a
recipient, title, content, and optional URL. It creates the existing
`Notification` record and then enqueues Pushover delivery when the recipient
has Pushover enabled. Existing Family notification producers use this entry
point; the general `Notification` model does not gain an external-delivery
callback.

Pushover configuration uses the existing per-user `ServiceSetting` model.
The service/provider vocabulary gains `notifications/pushover`. Encrypted
credentials contain the application token and user/group key. Non-secret
configuration contains enabled state. Tokens are not rendered back, logged,
or passed as job arguments.

The Pushover client uses the existing HTTP stack and the fixed endpoint
`https://api.pushover.net/1/messages.json`. It sends a plain-text version of
the sanitized notification content, a title, and an optional Dawarich URL.
No provider interface is introduced until a second provider creates a real
need for one.

## Availability And Eligibility

Pushover configuration is available wherever the Family feature is available,
on cloud or self-hosted installations. A user may configure Pushover before
joining a family.

Configuration alone never causes pushes. `Families::Notify` is called only for
a valid Family event involving its recipient, so a configured user outside a
family receives nothing. Eligibility is evaluated when the event is emitted,
not when the delivery job executes. This preserves valid departure messages,
such as notifying a user that they were removed after their membership has
already ended.

Future safety/freshness evaluators must require active Family availability,
active membership, and the tracked member's active consented sharing before
emitting an event.

## Initial Events

Pushover delivery covers Family events that already create in-app
notifications:

- Family creation.
- Invitation sent and accepted.
- Member joined, left, or removed.
- Incoming location request.

The contribution also notifies the requester when a location request is:

- Accepted, with a link to the Family page.
- Declined.
- Expired.

Sharing enabled/disabled/expired events and all safety alerts remain outside
this contribution.

## Data Flow

1. A Family service commits its domain state change.
2. The service calls `Families::Notify` for each intended recipient.
3. `Families::Notify` creates the in-app `Notification` record.
4. Existing model behavior broadcasts the notification through Turbo.
5. If the recipient has enabled Pushover, a delivery job is enqueued with the
   notification ID and optional URL.
6. The job reloads the recipient's encrypted credentials and sends the message.

The hourly location-request expiry job must process expired requests
individually rather than only using `update_all`, because each requester needs
one notification.

## Configuration

The Integrations UI adds a Pushover form containing:

- Application API token.
- User or group key.
- Enabled state.
- Save and validate action.
- Clear credentials action.

Saving validates credentials with Pushover's user-validation endpoint without
sending a message. Existing secrets are retained when password fields are left
blank.

## Failure Handling

Family actions never fail because notification creation or Pushover delivery
fails. Notification failures are reported through the existing exception
reporter and do not roll back domain state.

Pushover responses are classified as follows:

- HTTP 4xx or API `status: 0`: permanent failure, do not retry.
- HTTP 5xx or network failure: temporary failure, retry a small fixed number of
  times with a delay of at least five seconds.
- HTTP 2xx with API `status: 1`: successful delivery.

Titles and messages are converted to plain text and truncated to Pushover's
250-character title and 1,024-character message limits. The client uses TLS
verification and a fixed provider URL. Credentials and provider response
bodies are excluded from logs.

No delivery ledger is added. A timeout after Pushover accepts a request can
rarely produce a duplicate on retry because the Message API has no idempotency
key.

## Testing

Focused tests cover:

- Encrypted Pushover setting validation, save, retain, and clear behavior.
- Pushover request formatting and response classification with WebMock.
- Delivery-job behavior for configured, disabled, and missing settings.
- `Families::Notify` creating in-app notifications and enqueueing delivery.
- Accepted, declined, and expired location-request notifications.
- Existing Family notification producers using the new entry point.

Existing Family, notification, mailer, and settings request specs remain the
regression suite. No mobile-app or browser end-to-end tests are required.

## Future Safety Alerts

A later contribution can add a scheduled evaluator for explicit per-recipient
Family alert rules. It can compare each sharing member's latest complete point
and tracker metadata against configured thresholds, persist enough state to
suppress repeats and emit recovery messages, then call `Families::Notify`.

That work must separately define consent, monitoring relationships, stale
thresholds, battery semantics across trackers, recovery behavior, and
deduplication. None of those decisions are hidden inside the Pushover client.
