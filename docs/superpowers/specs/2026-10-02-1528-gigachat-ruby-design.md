# gigachat-ruby: Design Spec

- **Date:** 2026-10-02
- **Status:** awaiting user review
- **Target release:** 0.1.0

## 1. Goal

`gigachat-ruby` is a hand-written, plain-Ruby client for the GigaChat REST API. It covers every endpoint in `docs/rest_api.yml`, works out of the box (including TLS), streams robustly, and raises typed errors. It is tested with Minitest and ready to publish.

### Decisions already made

| Topic | Decision |
|---|---|
| Gem name | `gigachat-ruby`; `lib/gigachat-ruby.rb` is a shim that does `require "gigachat"` |
| Module | `GigaChat` (Zeitwerk inflection `"gigachat" => "GigaChat"`) |
| Ruby | `>= 4.0` |
| Architecture | Thin resources over one `Client#request` choke point, plus lenient response types (approach 1 of 3) |
| HTTP | Faraday 2 (`net_http` adapter) |
| Chat API | v2 is primary (`client.chat`); v1 stays fully supported (`client.chat.v1`) |
| TLS | Bundle the Russian Trusted Root CA and add it to a per-client cert store next to the system defaults; verification stays on |
| Live tests | Opt-in smoke suite (`rake test:live`) |
| README | English only (Russian translation goes to the backlog) |
| Rails | Backlog (`docs/backlog.md`) |

### Non-goals for 0.1.0

- Assistants, threads, `functions/convert`. These are in the Python SDK only, not in the spec.
- A separate async client. Faraday/Net::HTTP already yield under Ruby's Fiber scheduler (the `async` gem).
- RBS or Sorbet signatures.
- The Rails integration.
- Streamed (chunked) file downloads.
- Context-propagated headers (Fiber storage).
- Persistent connection pooling.

## 2. Public API

```ruby
require "gigachat"

GigaChat.configure do |c|                 # optional global defaults
  c.scope = "GIGACHAT_API_CORP"
  c.model = "GigaChat-2-Max"
end

client = GigaChat::Client.new              # kwargs > GigaChat.configure > GIGACHAT_* env > defaults
```

| Call | HTTP | Returns |
|---|---|---|
| `client.chat.create(messages:, model: nil, request_options: {}, **params)` | `POST {origin}/v2/chat/completions` | `Types::ChatCompletion` |
| `client.chat.stream(messages:, model: nil, request_options: {}, **params) { \|event\| }` | same, `stream: true` | the block form returns `Types::ChatCompletion` (accumulated); without a block, a `GigaChat::Stream` |
| `client.chat.v1.create(...)` / `client.chat.v1.stream(...)` | `POST {base}/chat/completions` | `Types::V1::ChatCompletion` / a stream of `Types::V1::ChatCompletionChunk` |
| `client.embeddings.create(input:, model: "Embeddings", **params)` | `POST {base}/embeddings` | `Types::Embeddings` |
| `client.models.list` / `client.models.retrieve(id)` | `GET {base}/models[/{id}]` | `Types::ModelList` / `Types::Model` |
| `client.files.upload(file, purpose: "general", filename: nil, content_type: nil)` | `POST {base}/files` (multipart) | `Types::FileObject` |
| `client.files.list` / `retrieve(id)` / `delete(id)` | `GET {base}/files`, `GET {base}/files/{id}`, `POST {base}/files/{id}/delete` | `Types::FileList` / `Types::FileObject` / `Types::FileDeleted` |
| `client.files.content(id)` | `GET {base}/files/{id}/content` | binary `String` (ASCII-8BIT) |
| `client.tokens_count(input:, model: nil)` | `POST {base}/tokens/count` | `Types::TokensCountList` |
| `client.balance` | `GET {base}/balance` | `Types::Balance` |
| `client.ai_check(input:, model:)` | `POST {base}/ai/check` | `Types::AiCheckResult` |
| `client.functions.validate(function = nil, **attrs)` | `POST {base}/functions/validate` | `Types::FunctionValidation` |
| `client.batches.create(input, method:)` | `POST {base}/batches?method=` (JSONL, `application/octet-stream`) | `Types::Batch` |
| `client.batches.list` / `retrieve(id)` | `GET {base}/batches[?batch_id=]` | `Types::BatchList` / `Types::Batch` |
| `client.batches.results(batch_or_file_id)` | `GET {base}/files/{output_file_id}/content` | `Array<Hash>` (parsed JSONL) |
| `client.token` | OAuth or `/token` | `Auth::AccessToken`; forces authentication |
| `client.request(method:, path:, query: nil, body: nil, headers: {}, type: nil, request_options: {})` | any | `type` instance, or the parsed JSON |
| `client.with_options(**overrides)` | n/a | a new `Client` |

### Rules

- **Pass-through.** Unknown `**params` go into the JSON body unchanged, so new API fields work without a gem release.
- **Model resolution.** `model` comes from the call, then from config. If chat, v1 chat or `tokens_count` still has no model, the client raises `ModelNotSpecifiedError` without sending anything. `embeddings` defaults to `"Embeddings"`. `ai_check` requires an explicit `model:`.
- **`stream: true` in `create`** raises `ArgumentError` pointing to `#stream`.
- **`request_options`** accepts `timeout`, `max_retries` and `headers`. Any other key raises `ArgumentError`.
- **`with_options`** shares the token manager unless an auth-related option changes: `credentials`, `scope`, `access_token`, `user`, `password`, `auth_url` or `base_url`.
- **Upload inputs.**
  - A `String` or `Pathname` is a file path.
  - An IO-like object (`#read`) is the content. Its filename comes from `#path` or from `filename:`; if neither is available, the call raises `ArgumentError`.
  - `content_type` defaults to the spec's format table (`Internal::MimeTypes`) and falls back to `application/octet-stream`.
- **Batch inputs.**
  - An `Array<Hash>` is encoded as JSONL.
  - A `String` or `Pathname` is a file path.
  - An IO-like object is read.
  - `method:` accepts `:chat_completions` or `:embedder` (Symbol or String).
- **Batch lookup and results.**
  - `batches.retrieve` takes the first element of `batches` from the list-shaped response. If the response is a bare object, it uses that object.
  - `batches.results` raises `GigaChat::Error` when the batch has no `output_file_id`.

## 3. Configuration

| Option | Env var | Default |
|---|---|---|
| `credentials` | `GIGACHAT_CREDENTIALS` | none |
| `scope` | `GIGACHAT_SCOPE` | `"GIGACHAT_API_PERS"` |
| `access_token` | `GIGACHAT_ACCESS_TOKEN` | none |
| `user` / `password` | `GIGACHAT_USER` / `GIGACHAT_PASSWORD` | none |
| `base_url` | `GIGACHAT_BASE_URL` | `"https://api.giga.chat/v1"` |
| `auth_url` | `GIGACHAT_AUTH_URL` | `"https://ngw.devices.sberbank.ru:9443/api/v2/oauth"` |
| `model` | `GIGACHAT_MODEL` | none |
| `timeout` | `GIGACHAT_TIMEOUT` | `60` (read/write, seconds) |
| `open_timeout` | none | `10` |
| `max_retries` | `GIGACHAT_MAX_RETRIES` | `2` |
| `verify_ssl_certs` | `GIGACHAT_VERIFY_SSL_CERTS` | `true` |
| `bundled_ca` | none | `true` |
| `ca_bundle_file` | `GIGACHAT_CA_BUNDLE_FILE` | none |
| `cert_file`, `key_file`, `key_file_password` | `GIGACHAT_CERT_FILE`, `GIGACHAT_KEY_FILE`, `GIGACHAT_KEY_FILE_PASSWORD` | none |
| `client_id`, `session_id` | none | none; sent as `X-Client-ID` / `X-Session-ID` |
| `logger` | none | none |

- The env var names match the Python SDK.
- Env vars are read when a `Client` is built, not at `require` time.
- Env strings are cast: booleans from `true/false/1/0`, numbers from `Integer`/`Float`.
- An unknown option raises `ConfigurationError`.
- `GigaChat.configure` yields `GigaChat.config`. `GigaChat.reset_config!` exists for tests.
- `Client#inspect` and `Configuration#inspect` mask `credentials`, `access_token`, `password` and `key_file_password`.

## 4. Transport

`Internal::Transport` owns two Faraday connections:
- the API connection, with `base_url` normalized to end in `/`;
- the OAuth connection.

Requests always use relative paths.

**URLs.**
- The v2 chat URL is built from `base_url`: a trailing `/vN` is replaced with `/v2/chat/completions`, and without a version suffix `v2/chat/completions` is appended. For example, `https://api.giga.chat/v1` becomes `https://api.giga.chat/v2/chat/completions`.

**Headers.**
- `User-Agent: gigachat-ruby/<VERSION> ruby/<RUBY_VERSION>`.
- `Authorization: Bearer <token>`, when a token strategy is active.
- `X-Client-ID` / `X-Session-ID` from the options.
- Per-request `request_options[:headers]` merge last.

**Bodies.**
- JSON bodies are written with `JSON.generate`, which keeps raw UTF-8 Cyrillic.
- JSON responses are parsed with `symbolize_names: true`.

**Response headers.** `x-request-id`, `x-session-id` and `x-client-id` are attached to top-level response objects.

**Threading.** One client may be shared across threads.

### TLS

- **Cert store.** `OpenSSL::X509::Store` is built with `set_default_paths`. The bundled `lib/gigachat/certs/russian_trusted_root_ca.pem` is added when `bundled_ca`, and `ca_bundle_file` is added when given. Additions are appended; they never replace the system store.
- **The bundled root:** Russian Trusted Root CA, Mintsifry, valid 2022-03-01 to 2032-02-27, SHA-256 `D2:6D:2D:02:31:B7:C3:9F:92:CC:73:85:12:BA:54:10:35:19:E4:40:5D:68:B5:BD:70:3E:97:88:CA:8E:CF:31`.
  - A test pins this fingerprint.
  - The servers send the intermediate CA themselves. A manual check on 2026-10-02 verified `api.giga.chat`, `ngw.devices.sberbank.ru:9443` and `gigachat.devices.sberbank.ru`.
- **`verify_ssl_certs: false`** sets `verify: false` and logs a warning once per client.
- **mTLS.** `cert_file`/`key_file` (`OpenSSL::PKey.read` with `key_file_password`) apply only to the API connection, as in the Python SDK.
- **Errors.** An `OpenSSL::SSL::SSLError` or `Faraday::SSLError` becomes `APIConnectionError`, with a hint pointing to the README's TLS section.

## 5. Authentication

Strategy, by precedence:
1. a static `access_token`;
2. `credentials` (OAuth);
3. `user`/`password` (`POST {base}/token` with HTTP Basic);
4. none: allowed only when `cert_file` is set. Otherwise the client raises `ConfigurationError` at the first request.

`Auth::TokenManager`:
- **Locking.** A `Mutex` with a double check inside the lock, so concurrent first calls fetch one token.
- **Usable token.** `expires_at` is 0 (a static token never expires locally) or more than 60 s in the future.
- **Units.** `expires_at` / `exp` values below 10^12 are seconds and are multiplied by 1000.
- **Response shapes.** Both `{access_token, expires_at}` and `{tok, exp}` are accepted.
- **The OAuth request** is a `POST auth_url` with:
  - `Authorization: Basic <credentials>`;
  - `RqUID: SecureRandom.uuid` (new for every call);
  - `Accept: application/json`;
  - a form body `scope=<scope>`.
- **OAuth failures** raise `AuthenticationError` (the body is `{code, message}`).
- **On a 401** from the API, when a refreshable strategy exists (credentials or user/password), the manager invalidates the token, fetches a new one and replays the request once. That replay does not count toward `max_retries`.
- **`Auth::AccessToken`** is `Data.define(:access_token, :expires_at)`; its `inspect` masks the token.

## 6. Retries

Handled by `Internal::RetryPolicy`, which takes an injectable `sleep` callable for tests.

- **Attempts:** `max_retries + 1` (2 retries by default; overridable per call).
- **Retried:**
  - statuses 429, 500, 502, 503 and 504;
  - `Faraday::ConnectionFailed`;
  - `Faraday::TimeoutError`, but only for GET.
- **Never retried:** SSL errors and other 4xx statuses.
- **Delay:**
  - `Retry-After`, as seconds or an HTTP date, capped at 60 s;
  - otherwise `0.5 * 2**attempt`, capped at 8 s, multiplied by a random factor in `0.75..1.0`.
- **Uploads.** The IO is rewound before a retry. A non-rewindable IO is not retried.
- **Streams.** A retry is allowed only before the first event reaches the caller.
- **Order:** the retry loop wraps auth, and auth wraps the HTTP call.

## 7. Errors

```
GigaChat::Error < StandardError
├─ ConfigurationError
├─ ModelNotSpecifiedError
├─ APIConnectionError
│   └─ APITimeoutError
└─ APIError                      # status, body (parsed JSON or String), headers, request_id
    ├─ BadRequestError             400
    ├─ AuthenticationError         401 (and OAuth failures)
    ├─ PermissionDeniedError       403
    ├─ NotFoundError               404
    ├─ RequestEntityTooLargeError  413
    ├─ UnprocessableEntityError    422
    ├─ RateLimitError              429, #retry_after (Float seconds or nil)
    └─ ServerError                 5xx
```

- `APIError.for(status:, body:, headers:)` picks the subclass. Any other status becomes a plain `APIError`.
- The message is `body[:message]` when present, plus the status and request id.
- `lib/gigachat/errors.rb` holds all of these. It is excluded from Zeitwerk and required explicitly.

## 8. Logging

This only happens when a `logger` is configured.
- **Info:** one line per request, e.g. `POST v2/chat/completions 200 812ms req=<x-request-id>`.
- **Debug:** retries (attempt, delay, reason) and token refreshes.
- **Never logged:** request or response bodies, `Authorization` headers, or credentials.

## 9. Response types

### `GigaChat::Types::Base`

- It holds the parsed hash, symbol-keyed and frozen.
- `attribute :name` declares a raw reader. `attribute :name, Type` and `attribute :name, Type, array: true` declare lazily converted, memoized readers.
- Unknown fields stay reachable through `#[]`, `#dig`, `#to_h` and `#to_json`.
- `#deconstruct_keys` supports pattern matching. `#==` compares raw data. `#inspect` is compact.
- `#to_json` lets you pass response objects back into requests, e.g. `messages: [*history, resp.message]`.
- Top-level responses also expose `#x_headers` (a Hash) and `#request_id`.
- List types include `Enumerable` over their items.

### Types

| Area | Types and helpers |
|---|---|
| Chat v2 | `ChatCompletion` (`model`, `created_at`, `thread_id`, `messages`, `finish_reason`, `usage`, `additional_data`)<br>Helpers: `#text` (joined text of assistant content parts, or `""`), `#message` (first assistant message), `#function_call` (first one across parts), `#files` (all `FileRef`s) |
| | `Message` (`role`, `message_id`, `tools_state_id`, `content` → `ContentPart`; `#text`) |
| | `ContentPart` (`text`, `files` → `FileRef(id, target, mime)`, `function_call`, `tool_execution` → `ToolExecution(name, status, seconds_left, censored)`, `logprobs`, `inline_data`) |
| | `Usage` (`input_tokens`, `input_tokens_details`, `output_tokens`, `total_tokens`) |
| | `ChatEvent`: the `ChatCompletion` fields plus `#type`, `#delta?`, `#done?`, `#tool_in_progress?`, `#tool_completed?`, `#text` |
| Chat v1 | `V1::ChatCompletion` (`choices`, `created`, `model`, `object`, `usage`; `#text`)<br>`V1::Choice` (`message`, `index`, `finish_reason`)<br>`V1::Message` (`role`, `content`, `functions_state_id`, `function_call`, `name`, `created`)<br>`V1::Usage` (`prompt_tokens`, `completion_tokens`, `precached_prompt_tokens`, `total_tokens`)<br>`V1::ChatCompletionChunk` (`choices[].delta` as `V1::Message`, `usage`) |
| Shared | `FunctionCall` (`name`, `arguments`). `#arguments` always returns a Hash and parses a JSON string. The spec says "string", but its examples and both SDKs use an object. |
| Other | `Embeddings` (`data` → `Embedding(embedding, index, usage)`, `model`; `#vectors`)<br>`Model` (`id`, `object`, `owned_by`, `type`), `ModelList`<br>`FileObject` (`id`, `bytes`, `created_at`, `filename`, `object`, `purpose`, `access_policy`, `modalities`), `FileList`, `FileDeleted` (`id`, `deleted`, `access_policy`)<br>`Balance` (`balance` → `BalanceEntry(usage, value)`), `TokensCountList` (→ `TokensCount(object, tokens, characters)`)<br>`AiCheckResult` (`category`, `characters`, `tokens`, `ai_intervals`; `#ai?`, `#human?`, `#mixed?`)<br>`FunctionValidation` (`status`, `message`, `json_ai_rules_version`, `errors`/`warnings` → `Issue(description, schema_location)`; `#valid?` when `errors` is empty)<br>`Batch` (`id`, `method`, `request_counts`, `status`, `output_file_id`, `created_at`, `updated_at`; `#created?`, `#in_progress?`, `#completed?`), `BatchList` |

`Auth::AccessToken` and `Internal::SSEDecoder::Event` use `Data.define`. Everything returned from the API is a `Types::Base`.

### Request normalization (v2 only, deliberately minimal)

- `content: "str"` becomes `[{ text: "str" }]`, and a single Hash becomes `[hash]`.
- Missing `model` is filled from config.
- Nothing else is rewritten. In particular, `tools_state_id` and `tool_state_id` are sent exactly as given (see section 13).

## 10. Streaming

### `Internal::SSEDecoder`

- It is fed raw chunks and keeps a binary buffer.
- It splits lines on `\r\n`, `\n` or `\r` and forces UTF-8 only on complete lines.
- It strips a leading BOM and ignores `:` comments.
- It accumulates `event`, `data` (several data lines are joined with `\n`) and `id`, and emits `Event(event:, data:, id:)` on a blank line. `#finish` flushes a trailing event.

### `GigaChat::Stream`

It includes `Enumerable` and is built by the chat resources.

- **Lazy.** The HTTP request starts on the first `#each`, which runs Faraday with `on_data`. Without a block, `#each` returns an `Enumerator`.
- **Errors.**
  - A non-2xx status, checked inside `on_data` through `env.status`, buffers the body and then raises `APIError.for`.
  - A 2xx response whose content type isn't `text/event-stream` raises `APIError`.
- **End of stream.**
  - v1 parses each `data:` as `V1::ChatCompletionChunk` and stops at `data: [DONE]`.
  - v2 parses each event into a `ChatEvent` with `type = event`, yields it, and stops after `response.message.done`.
  - An `event: error` raises `APIError.for`, using the payload's `status`, or 500 when absent.
- **Accumulation.** Every yielded event also feeds an accumulator:
  - `Internal::ChatAccumulator` (v2) groups by message position. It concatenates text into one text part, appends non-text parts, and keeps the last non-nil `role`, `tools_state_id`, `finish_reason`, `usage`, `model`, `created_at` and `thread_id`.
  - `Internal::V1ChatAccumulator` groups by choice index. It concatenates `content` and keeps the last non-nil `function_call`, `functions_state_id`, `finish_reason` and `usage`.
- **Accessors.**
  - `#response` returns the accumulated `ChatCompletion` / `V1::ChatCompletion`, consuming the stream first if needed.
  - The block form of `chat.stream` returns `#response`.
  - `#text` is an `Enumerator` of text deltas.
- **Lifetime.** Breaking out of `#each` closes the connection. A stream is single-use, so a second `#each` raises `GigaChat::Error`.
- **Timeouts.** The read timeout applies to the gap between chunks.

## 11. Layout and packaging

```
gigachat-ruby.gemspec  Gemfile  Rakefile  README.md  CHANGELOG.md  LICENSE.txt  .rubocop.yml
bin/console  bin/setup  .github/workflows/ci.yml
lib/gigachat-ruby.rb
lib/gigachat.rb                       # Zeitwerk (for_gem, warn_on_extra_files: false), inflections, configure/config
lib/gigachat/version.rb configuration.rb client.rb stream.rb errors.rb
lib/gigachat/auth/token_manager.rb access_token.rb
lib/gigachat/internal/transport.rb retry_policy.rb sse_decoder.rb mime_types.rb chat_accumulator.rb v1_chat_accumulator.rb
lib/gigachat/resources/base.rb chat.rb chat_v1.rb embeddings.rb models.rb files.rb functions.rb batches.rb
lib/gigachat/types/*.rb  lib/gigachat/types/v1/*.rb
lib/gigachat/certs/russian_trusted_root_ca.pem
```

Zeitwerk inflections: `gigachat` becomes `GigaChat`, `sse_decoder` becomes `SSEDecoder` and `chat_v1` becomes `ChatV1`. `errors.rb` is ignored by the loader and required explicitly. The loader also ignores the shim `lib/gigachat-ruby.rb`, because `gigachat-ruby` is not a valid constant name and eager loading would fail. An eager-load test (`loader.eager_load(force: true)`) guards this.

**Gemspec.**
- `required_ruby_version >= 4.0` and `rubygems_mfa_required`.
- MIT license.
- Author Aleksandr Dryzhuk, `dev@ad-it.pro`.
- Homepage `https://github.com/amdest/gigachat-ruby`; changelog URI on the `master` branch.
- `files` covers `lib/**`, `README.md`, `CHANGELOG.md` and `LICENSE.txt`.
- **Runtime dependencies:** `faraday ~> 2.14`, `faraday-multipart ~> 1.2`, `zeitwerk ~> 2.8`.
- **Development dependencies (Gemfile, alphabetical):** `irb`, `minitest ~> 6.0`, `rake`, `rubocop`, `rubocop-minitest`, `rubocop-rake`, `webmock`.

**RuboCop.** `TargetRubyVersion` 4.0; double quotes; frozen string literals enforced; line length 120; method length 40; ABC size 40; class length 200; cyclomatic complexity 10; perceived complexity 15. Test files are excluded from the metrics cops.

**CI.** A GitHub Actions workflow runs `bundle exec rake` on Ruby 4.0.

## 12. Testing

- **Setup.** `test/test_helper.rb` does `WebMock.disable_net_connect!`, clears and restores `GIGACHAT_*` env vars around each test, and calls `GigaChat.reset_config!`.
- **Fixtures.** `test/fixtures/` holds JSON response bodies taken from the spec examples, and `.sse` transcripts for v1 and v2.
- **Unit tests**, about one focused test per behavior:
  - configuration precedence and casting;
  - token manager: buffer, units, both response shapes, the single 401 replay, a concurrent fetch happening once;
  - TLS: the fingerprint pin, `ca_bundle_file` appended, the warning when verification is off;
  - retry policy: statuses, `Retry-After` in both forms, GET-only timeouts, the cap;
  - error mapping;
  - SSE decoder: split lines, CRLF, a multibyte Cyrillic character split across chunks, comments, multi-line data, the trailing flush;
  - stream: `[DONE]`, the `done` event, `event: error`, a non-2xx body, breaking closes the connection, single use, no retry after the first event;
  - both accumulators;
  - the `Types::Base` contract;
  - each resource: method, path, headers, body, and the returned type.
- **`rake test`** runs the unit tests. **`rake`** runs the tests and RuboCop.
- **`rake test:live`** runs `test/live/` and skips everything unless `GIGACHAT_CREDENTIALS` is set.
  - `balance` runs only on PERS/B2B scopes; `batches` and `ai_check` only on CORP.
  - Coverage: token, models, chat v2 and v1 (create and stream), embeddings, tokens count, the file lifecycle (upload a small `.txt`, retrieve, content, delete), and function validation.

## 13. Open questions settled by the live smoke suite

1. **v2 stream payload shape.** The spec's example shows v1-style `choices[].delta`; the Python SDK, recorded against the live API, parses `messages[].content[]`. We implement the Python shape. Because types are lenient, the raw data stays reachable if it differs.
2. **`tool_state_id` vs `tools_state_id`.** The spec's v2 request uses `tool_state_id`, while responses and the Python SDK use `tools_state_id`. We send whatever the caller passes.
3. **`files.content` `Accept` header.** The spec says `application/octet-stream`, while the Python SDK sends `application/jpg`. We send `*/*`.
4. **`GET /batches` shape.** The spec says `{batches: [...]}`, while the JS SDK assumes a bare array. We implement the spec and accept both.

## 14. Documentation

**README (English):**
- Installation.
- TLS note (the bundled CA, opting out, `ca_bundle_file`).
- Configuration table.
- Usage per endpoint.
- Streaming.
- Errors (status-to-class table).
- Retries and timeouts.
- Logging.
- Response metadata (`request_id`).
- Running live tests.

**Also:** a CHANGELOG in Keep a Changelog format starting at 0.1.0, and YARD comments only on non-obvious public methods.
