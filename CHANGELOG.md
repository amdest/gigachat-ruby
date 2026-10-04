# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [0.1.2] - 2026-10-04

### Fixed

- Chat streams (v1 and v2) now arrive as they are generated. GigaChat delivers server-sent events incrementally
  only over HTTP/2 and buffers the whole answer over HTTP/1.1, which is all Net::HTTP (Faraday's default
  adapter) speaks, so every event used to arrive at once after the answer was complete.
- Stopping a stream early (breaking out of the block, or an exception from it) resets the connection, so
  GigaChat stops generating.

### Changed

- Chat streams use [httpx](https://gitlab.com/os85/httpx) over HTTP/2; every other request stays on Faraday.
  New runtime dependency: `httpx ~> 1.8`. Proxies from `HTTP(S)_PROXY` are not applied to streams.

## [0.1.1] - 2026-10-02

### Added

- `GigaChat::PaymentRequiredError` for HTTP 402 (token balance exhausted). The OpenAPI spec doesn't list
  this status, but the API returns it in practice.

## [0.1.0] - 2026-10-02

### Added

- `GigaChat::Client`:
  - authentication by OAuth (credentials + scope), static token, user/password or mTLS;
  - thread-safe token caching with proactive refresh and a single replay on 401.
- Chat v2 (`client.chat.create` / `client.chat.stream`) and v1 (`client.chat.v1`), with SSE streaming,
  typed events and accumulated responses.
- Embeddings, models, files (upload/list/retrieve/delete/content), token counting, balance, AI-text detection,
  function validation, and batches (create/list/retrieve/results).
- Lenient typed response objects:
  - unknown fields are kept;
  - `request_id` is exposed;
  - pattern matching is supported.
- Retries with exponential backoff and `Retry-After` support; a typed error hierarchy.
- The bundled Russian Trusted Root CA, added to a per-client certificate store.
- An opt-in live smoke suite (`rake test:live`).
