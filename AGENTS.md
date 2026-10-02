# AGENTS.md

Repository guidance for coding agents. Global user rules (`~/.agents/AGENTS.md`) still apply; this file adds what is specific to this gem.

## Project Summary

`gigachat-ruby` is a hand-written Ruby client for the [GigaChat REST API](https://developers.sber.ru/docs/ru/gigachat/api/reference/rest/gigachat-api) (Sber).

- Gem name: `gigachat-ruby` (the name `gigachat` is taken on RubyGems). Entry point: `require "gigachat"`; `lib/gigachat-ruby.rb` is only a shim for Bundler auto-require.
- Top-level module: `GigaChat` (brand casing; Zeitwerk needs the `"gigachat" => "GigaChat"` inflection).
- Plain Ruby first. Rails 8+ integration is optional, must never load unless Rails is present, and is currently in the backlog (`docs/backlog.md`).
- Ruby `>= 4.0`. Use modern idioms where they read well: pattern matching, endless methods, `Data.define` for small immutable values.
- HTTP: Faraday. Autoloading: Zeitwerk. Tests: Minitest + WebMock. Lint: RuboCop.

## Sources of Truth

1. `docs/rest_api.yml`: the OpenAPI 3.1 spec (in Russian). It is authoritative for endpoints, fields and error shapes.
2. `docs/GigaChat API.postman_collection.json`: request examples, v1 only.
3. Reference SDKs, for behavior the spec doesn't cover:
   - [ai-forever/gigachat](https://github.com/ai-forever/gigachat) (Python 0.2.3, the most complete);
   - [ai-forever/gigachat-js](https://github.com/ai-forever/gigachat-js) (v1 only, lags behind).
4. [openai/openai-ruby](https://github.com/openai/openai-ruby): a structural inspiration only (client choke point, retries, errors, SSE decoding). Do not copy its code-generated type machinery.

If the spec and an SDK disagree, follow the spec. Note the discrepancy in a code comment or test.

## API Surface (from the spec)

| Area | Endpoint |
|---|---|
| OAuth token | `POST https://ngw.devices.sberbank.ru:9443/api/v2/oauth` (separate host) |
| Chat v2 (primary) | `POST {origin}/v2/chat/completions` |
| Chat v1 | `POST {base}/chat/completions` |
| Embeddings | `POST {base}/embeddings` |
| Models | `GET {base}/models`, `GET {base}/models/{model}` |
| Files | `POST {base}/files` (multipart), `GET {base}/files`, `GET {base}/files/{id}`, `GET {base}/files/{id}/content`, `POST {base}/files/{id}/delete` |
| Usage | `POST {base}/tokens/count`, `GET {base}/balance` |
| AI check | `POST {base}/ai/check` |
| Functions | `POST {base}/functions/validate` |
| Batches | `POST {base}/batches?method=chat_completions\|embedder` (JSONL body), `GET {base}/batches[?batch_id=]` |

The default `{base}` is `https://api.giga.chat/v1`.

## API Quirks

These are easy to get wrong:

- **OAuth request.** It needs `Authorization: Basic <credentials>`, a fresh `RqUID` (UUID4) on every call, and a form-encoded `scope`. Valid scopes are `GIGACHAT_API_PERS`, `GIGACHAT_API_B2B` and `GIGACHAT_API_CORP`. OAuth is rate-limited to 10 req/s.
- **Token lifetime.** Tokens live 30 minutes. `expires_at` is in **milliseconds**, so normalize any value below 10^12 as seconds. Refresh ahead of expiry, and re-authenticate exactly once on a 401.
- **v2 chat URL.** It is built from the origin: `https://api.giga.chat/v1` becomes `https://api.giga.chat/v2/chat/completions`. Every other endpoint is relative to `base_url`.
- **Faraday paths.** Keep a trailing slash on `base_url` and use relative paths. A leading `/` drops the `/v1` prefix.
- **SSE formats differ by version.**
  - v1 sends `data: {json}` lines and ends with `data: [DONE]`.
  - v2 sends named events (`response.message.delta`, `response.message.done`, `response.tool.in_progress`, `response.tool.completed`) and has no `[DONE]`.
  - Buffer partial lines across network chunks, and decode UTF-8 (Cyrillic) only on complete lines.
- **Function arguments.** In v1, `function_call.arguments` arrives as a JSON **object**, even though the spec calls it a string.
- **Deleting files.** It is `POST /files/{id}/delete`, not `DELETE`.
- **Batches.** `GET /batches` returns `{ "batches": [...] }` (per the spec). Results are fetched as JSONL through `GET /files/{output_file_id}/content`.
- **Restricted endpoints.** `balance` only works for prepaid packages (it returns 403 on pay-as-you-go). `batches` and `ai/check` only work for CORP (pay-as-you-go).
- **TLS.** Every GigaChat host chains to the **Russian Trusted Root CA** (Mintsifry, valid until 2032-02-27). Ruby's default OpenSSL store rejects it. Never "fix" this by disabling verification in code or tests.
- **Response headers.** Every response carries `x-request-id`, `x-session-id` and `x-client-id`. Keep them on response objects for support tickets.

## Working Rules

- Code, comments, YARD and commit messages are in English. Spec text is Russian; translate it, don't paste it.
- Read the relevant spec section before implementing or changing an endpoint.
- Keep resources thin. Transport, auth, retries and errors belong in the shared client layer, not in individual resources.
- Response objects must tolerate unknown fields: the API adds fields without notice.
- Never log or `inspect` secrets (`credentials`, `access_token`, `password`, the `Authorization` header).
- Runtime dependencies stay minimal. Justify every new one in the PR or commit body.
- Rails-specific code goes only under `lib/gigachat/rails/` and only after the backlog item is picked up.
- Deferred ideas go to `docs/backlog.md`, not into the current change.

## Testing

- Minitest only (never RSpec). Follow AAA (Arrange-Act-Assert) and give assertions messages.
- Unit tests stub HTTP with WebMock. Build fixtures from the spec examples.
- Live smoke tests are opt-in. They run only when `GIGACHAT_CREDENTIALS` is set; `GIGACHAT_SCOPE` decides which scope-restricted endpoints are skipped. They must never run in CI by default.
- Tests must not sleep for real: stub the backoff sleep.

## Version Control

- Conventional Commits (`type(scope): description`).
- Work on `dev` or on feature branches cut from `dev`. `master` receives release squash-merges only.

## Design Docs

- Specs: `docs/superpowers/specs/`. Plans: `docs/superpowers/plans/`. Backlog: `docs/backlog.md`.
- The current architecture spec is `docs/superpowers/specs/2026-10-02-1528-gigachat-ruby-design.md`. Read it before structural changes, and update it when a decision changes.
- Dated files use `YYYY-MM-DD-HHMM-slug.md`.
