# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

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
