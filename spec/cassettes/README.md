# Provider cassettes

These VCR cassettes back `spec/models/ai/adapters_spec.rb`. There is one folder per
provider (`gemini/`, `anthropic/`, `openai/`), each holding:

| Cassette | What it shows |
|---|---|
| `success.yml` | 200 with three meals as JSON text |
| `invalid_key.yml` | Gemini 400 `API_KEY_INVALID`; Anthropic and OpenAI 401 |
| `rate_limit.yml` | 429 for a per-minute limit |
| `quota.yml` | The provider's "out of credit / quota" body: Gemini 429 with a `PerDay` quota id, Anthropic 400 "credit balance is too low", OpenAI 429 `insufficient_quota` |
| `malformed_prose.yml`, `malformed_broken_json.yml`, `malformed_wrong_shape.yml` | 200, but the model's text is prose, cut-off JSON, or the wrong shape |

Timeouts have no cassette. The spec uses WebMock's `to_timeout`.

## They are hand-authored

We had no real API keys when these were written, so nobody recorded them from a live
API. Each one is still in the provider's real wire format:

- **Request**: the exact method, URL, headers and JSON body our adapter sends through
  RubyLLM 2.1. They were captured by running the adapter against WebMock. Endpoints:
  - Gemini: `POST https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent`
  - Anthropic: `POST https://api.anthropic.com/v1/messages`
  - OpenAI: `POST https://api.openai.com/v1/responses` (RubyLLM's default OpenAI protocol)
- **Response**: written by hand from each provider's documented response and error
  bodies, in the shape RubyLLM parses:
  - Gemini: `candidates[0].content.parts[].text`
  - Anthropic: `content[].text`
  - OpenAI: `output[type=message].content[type=output_text].text`

Keys never appear in a cassette. Auth headers hold placeholders (`<GEMINI_API_KEY>`,
`<ANTHROPIC_API_KEY>`, `Bearer <OPENAI_API_KEY>`), and a spec fails if any test key or
real-looking key shows up in these files.

Requests are matched on method and URI only. The body carries the prompt, and specs
check the body directly. When you change the prompt, these files don't need to change.

## Re-recording with real keys

Playback only by default (`record: :none`), so no spec reaches the network. To refresh
the success cassettes against the live APIs:

```sh
rm spec/cassettes/gemini/success.yml   # VCR only records interactions it doesn't already have
VCR_RECORD=new_episodes \
  GEMINI_API_KEY=... GEMINI_MODEL=gemini-2.5-flash \
  ANTHROPIC_API_KEY=... ANTHROPIC_MODEL=... \
  OPENAI_API_KEY=... OPENAI_MODEL=... \
  bundle exec rspec spec/models/ai/adapters_spec.rb -e success
```

`VCR_RECORD=all` re-records everything without deleting files first. Keys come only from
the environment, and `spec/support/vcr.rb` replaces them with placeholders before
anything is written. Check `git diff spec/cassettes` before you commit.

- **`invalid_key`** records live, because the spec always sends a deliberately bad key.
- **`rate_limit`** and **`quota`** can't be triggered on demand. Keep these
  hand-authored. Update them when a provider changes its error body.
- **`malformed_*`** stay hand-authored. A live model won't reliably send back bad output.
- **A real recording** won't contain the patient-name test input. Redaction runs before
  the request is sent.
