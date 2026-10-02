# gigachat-ruby

Ruby client for Sber's [GigaChat REST API](https://developers.sber.ru/docs/ru/gigachat/api/reference/rest/gigachat-api).
It covers chat completions (v2 and v1) with streaming, embeddings, files, batches, token counting,
AI-text detection and function validation.

- Plain Ruby (4.0+). No Rails required.
- Automatic OAuth token management, retries with backoff, and typed errors.
- Works out of the box with GigaChat's TLS certificates (see [TLS](#tls)).

## Installation

```ruby
# Gemfile
gem "gigachat-ruby"
```

```ruby
require "gigachat"
```

## Quick start

```ruby
client = GigaChat::Client.new(credentials: ENV["GIGACHAT_CREDENTIALS"], model: "GigaChat-2-Max")

completion = client.chat.create(messages: [{ role: "user", content: "Привет! Расскажи о себе." }])
puts completion.text
```

`credentials` is the base64 **Authorization key** from your GigaChat Studio project. The client exchanges it for
a 30-minute access token, caches the token, and refreshes it before it expires.

## Configuration

Options are resolved in this order: keyword arguments, then `GigaChat.configure`, then `GIGACHAT_*` environment
variables, then defaults.

```ruby
GigaChat.configure do |c|
  c.scope = "GIGACHAT_API_CORP"
  c.model = "GigaChat-2-Max"
end

client = GigaChat::Client.new # picks up the global config and GIGACHAT_* variables
```

| Option | Env var | Default |
|---|---|---|
| `credentials` | `GIGACHAT_CREDENTIALS` | — |
| `scope` | `GIGACHAT_SCOPE` | `GIGACHAT_API_PERS` (also `GIGACHAT_API_B2B`, `GIGACHAT_API_CORP`) |
| `access_token` | `GIGACHAT_ACCESS_TOKEN` | — (a pre-obtained token) |
| `user`, `password` | `GIGACHAT_USER`, `GIGACHAT_PASSWORD` | — (the `/token` flow; needs a `base_url` that serves it) |
| `base_url` | `GIGACHAT_BASE_URL` | `https://api.giga.chat/v1` |
| `auth_url` | `GIGACHAT_AUTH_URL` | `https://ngw.devices.sberbank.ru:9443/api/v2/oauth` |
| `model` | `GIGACHAT_MODEL` | — (required for chat and token counting) |
| `timeout` / `open_timeout` | `GIGACHAT_TIMEOUT` / — | `60` / `10` seconds |
| `max_retries` | `GIGACHAT_MAX_RETRIES` | `2` |
| `verify_ssl_certs` | `GIGACHAT_VERIFY_SSL_CERTS` | `true` |
| `bundled_ca` | — | `true` |
| `ca_bundle_file` | `GIGACHAT_CA_BUNDLE_FILE` | — |
| `cert_file`, `key_file`, `key_file_password` | same names, `GIGACHAT_` prefix | — (mTLS) |
| `client_id`, `session_id` | — | — (sent as `X-Client-ID` / `X-Session-ID`) |
| `logger` | — | — |

The environment variable names match the official Python SDK, so one `.env` file works for both.

## TLS

GigaChat's certificates chain to the **Russian Trusted Root CA** (Ministry of Digital Development). Ruby's default
OpenSSL store doesn't include it, so plain HTTPS calls fail with `certificate verify failed`.

This gem ships that root certificate (valid until 2032-02-27; its SHA-256 fingerprint is pinned in the test suite).
It adds the certificate to a **per-client** certificate store, next to your system roots, so:

- verification stays on;
- nothing changes for other HTTPS connections in your process.

Options:

- `bundled_ca: false` uses only the system store, for example when your OS image already trusts the root.
- `ca_bundle_file: "/path/to/ca.pem"` adds more trusted CAs; they are appended, never replacing the defaults.
- `verify_ssl_certs: false` disables verification. Use it only for debugging; the client logs a warning.

## Chat (v2)

```ruby
completion = client.chat.create(
  messages: [
    { role: "system", content: "Ты — профессиональный переводчик на английский язык." },
    { role: "user", content: "GigaChat — это сервис для диалога с пользователем." }
  ],
  model_options: { temperature: 0.3 }
)

completion.text                # assistant text
completion.usage.total_tokens
completion.finish_reason       # "stop", "length", "function_call", ...
completion.request_id          # x-request-id, useful for support tickets
```

`content: "text"` is shorthand for v2 content parts (`[{ text: "text" }]`). Any other keyword (`tools`,
`tool_config`, `model_options`, `user_info`, `ranker_options`, …) is sent to the API as is.

Keep the history by passing previous messages back, including response objects:

```ruby
history = [{ role: "user", content: "Привет!" }]
reply = client.chat.create(messages: history)
history += [reply.message, { role: "user", content: "Расскажи анекдот" }]
client.chat.create(messages: history)
```

### Streaming

```ruby
# A block streams events and returns the accumulated completion.
final = client.chat.stream(messages: [{ role: "user", content: "Напиши стих" }]) do |event|
  print event.text if event.delta?
end
final.usage

# Without a block you get a lazy, single-use stream.
stream = client.chat.stream(messages: [{ role: "user", content: "Напиши стих" }])
stream.text.each { print it } # text deltas only
stream.response               # accumulated completion
```

Breaking out of the block closes the connection.

### Function calling

```ruby
weather = {
  name: "weather_forecast",
  description: "Weather forecast for a city",
  parameters: { type: "object", properties: { location: { type: "string" } }, required: ["location"] }
}
tools = [{ functions: { specifications: [weather] } }]
messages = [{ role: "user", content: "Какая погода в Туле?" }]

first = client.chat.create(messages:, tools:)
if (call = first.function_call)
  result = { temperature: 12 } # call your code with call.arguments (a Hash)
  messages += [
    first.message, # carries tool_state_id, which ties the result to this call
    { role: "tool", content: [{ function_result: { name: call.name, result: JSON.generate(result) } }] }
  ]
  puts client.chat.create(messages:, tools:).text
end
```

Pass the assistant message back unchanged: it carries the `tool_state_id` the API returned (also readable as
`first.message.tools_state_id`).

### Structured output

```ruby
client.chat.create(
  messages: [{ role: "user", content: "27 октября 2023 года у меня родился сын" }],
  model_options: {
    response_format: {
      type: "json_schema",
      schema: { type: "object", properties: { date: { type: "string" } }, required: ["date"] },
      strict: true
    }
  }
)
```

## Chat (v1)

The original `/chat/completions` API is fully supported:

```ruby
client.chat.v1.create(messages: [{ role: "user", content: "Привет!" }]).text
client.chat.v1.stream(messages: [{ role: "user", content: "Привет!" }]) { |chunk| print chunk.text }
```

## Embeddings

```ruby
client.embeddings.create(input: ["Первый текст", "Второй текст"]).vectors # model defaults to "Embeddings"
client.embeddings.create(input: "Текст", model: "EmbeddingsGigaR")
```

## Models

```ruby
client.models.list.map(&:id)
client.models.retrieve("GigaChat-2-Max")
```

## Files

```ruby
file = client.files.upload("report.pdf")                      # a path or Pathname
file = client.files.upload(io, filename: "notes.txt")        # any IO; filename needed when the IO has no path
client.chat.create(messages: [{ role: "user", content: [{ text: "Summarize", files: [{ id: file.id }] }] }])

client.files.list.map(&:filename)
client.files.retrieve(file.id)
client.files.content(image_id)                                # binary String, e.g. a generated image
client.files.delete(file.id).deleted?
```

## Token counting and balance

```ruby
client.tokens_count(input: ["Я к вам пишу — чего же боле?"]).map(&:tokens)
client.balance.map { [it.usage, it.value] } # prepaid packages only (403 on pay-as-you-go)
```

## AI-text detection

```ruby
client.ai_check(input: text, model: "GigaCheckClassification").category # "ai", "human" or "mixed"
```

## Function validation

```ruby
result = client.functions.validate(weather)
result.valid?
result.warnings.map(&:description)
```

## Batches

Batches are available on pay-as-you-go (`GIGACHAT_API_CORP`).

```ruby
requests = [
  { id: "1", request: { model: "GigaChat-2", messages: [{ role: "user", content: "Привет" }] } }
]
batch = client.batches.create(requests, method: :chat_completions) # or method: :embedder
batch = client.batches.retrieve(batch.id)
client.batches.results(batch) if batch.completed?                 # parsed JSONL lines
```

## Errors

| Status | Error |
|---|---|
| 400 | `GigaChat::BadRequestError` |
| 401 | `GigaChat::AuthenticationError` |
| 403 | `GigaChat::PermissionDeniedError` |
| 404 | `GigaChat::NotFoundError` |
| 413 | `GigaChat::RequestEntityTooLargeError` |
| 422 | `GigaChat::UnprocessableEntityError` |
| 429 | `GigaChat::RateLimitError` (`#retry_after`) |
| 5xx | `GigaChat::ServerError` |
| network | `GigaChat::APIConnectionError`, `GigaChat::APITimeoutError` |

Every `GigaChat::APIError` carries `#status`, `#body`, `#headers` and `#request_id`. All errors inherit from
`GigaChat::Error`.

## Retries and timeouts

Retries apply to statuses 429, 500, 502, 503 and 504, to connection failures, and to timeouts on GET requests.
There are 2 retries by default:

- the delay is exponential with jitter, capped at 8 seconds;
- `Retry-After` wins over the default delay, capped at 60 seconds;
- streams are retried only before the first event arrives.

You can override this per call:

```ruby
client.chat.create(messages:, request_options: { timeout: 300, max_retries: 0, headers: { "X-Client-ID" => "u-1" } })
client.with_options(session_id: "chat-42").chat.create(messages:) # a copy that reuses the access token
```

## Logging

```ruby
client = GigaChat::Client.new(logger: Logger.new($stdout))
# GigaChat: POST https://api.giga.chat/v2/chat/completions 200 812ms req=…
```

The log never contains request or response bodies, tokens or credentials.

## Low-level requests

```ruby
client.request(method: :get, path: "models") # auth, retries and error mapping included
```

## Development

```sh
bundle install
bundle exec rake            # unit tests + RuboCop
GIGACHAT_CREDENTIALS=… GIGACHAT_SCOPE=GIGACHAT_API_PERS bundle exec rake test:live   # real API, opt-in
```

## License

MIT. See `LICENSE.txt`.
