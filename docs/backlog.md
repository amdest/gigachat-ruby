# Backlog

Deferred work. Pick items up only after the core client is complete and tested.

## Rails 8+ integration (optional extension)

Loaded only when Rails is present; lives under `lib/gigachat/rails/`. Candidate features, to be prioritized when we return to it:

- **Railtie + install generator.** `config.gigachat` and `Rails.application.credentials.gigachat` feed the default client. `bin/rails g gigachat:install` writes `config/initializers/gigachat.rb`.
- **Shared token cache.** Keep the 30-minute access token in `Rails.cache` (Solid Cache), so Puma workers and Solid Queue jobs reuse one token instead of each calling OAuth, which is limited to 10 req/s. The core token manager needs a pluggable store for this.
- **Notifications + logger.** Emit `ActiveSupport::Notifications` events (for example `request.gigachat`) with model, usage and duration, and use `Rails.logger` as the default logger.
- **SSE streaming helper.** A controller concern that pipes a chat stream to the browser through `ActionController::Live`.

## Core client: deferred from 0.1.0

- **Russian README** (`README.ru.md`), once the API surface settles.
- **RBS signatures** (`sig/gigachat.rbs`), hand-written and checked by `rbs validate`.
- **Endpoints only the Python SDK has:** assistants, threads, `functions/convert`. Add them only if they appear in the official spec.
- **Streamed file downloads:** `files.content(id) { |chunk| ... }` for large files (3D models, batch outputs).
- **Context-propagated headers:** `GigaChat.with_headers(session_id:) { ... }` built on Fiber storage, in the spirit of Python's contextvars.
- **Persistent HTTP connections** (keep-alive or a pool), if profiling shows that per-request connection setup matters.
