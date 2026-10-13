# S1-mini research note

Read 2026-10-13 from Hugging Face revision `88f6b15896c73bbb13a3b596e0afe8ea0d5150b4`
(`superwhisper/s1-mini`) and `34add00a48a2e5d24e5a4ee5405a99620a3a240c`
(`superwhisper/s1-mini-GGUF`), both last modified 2026-08-28.

Sources:

- Model card: <https://huggingface.co/superwhisper/s1-mini> (README.md)
- GGUF card: <https://huggingface.co/superwhisper/s1-mini-GGUF> (README.md)
- License: <https://huggingface.co/superwhisper/s1-mini/blob/main/LICENSE>
  (byte-identical in the GGUF repository)
- Notice: <https://huggingface.co/superwhisper/s1-mini/blob/main/NOTICE> and
  <https://huggingface.co/superwhisper/s1-mini-GGUF/blob/main/NOTICE>
- `chat_template.jinja`, `generation_config.json` in `superwhisper/s1-mini`
- Announcement: <https://superwhisper.com/blog/s1> (2026-08-19)
- Ollama API: <https://github.com/ollama/ollama/blob/main/docs/api.md> and
  `server/routes.go` (raw mode and `think` handling)
- Hugging Face Ollama guide: <https://huggingface.co/docs/hub/ollama>

## What it is

S1-mini by Superwhisper is a 0.6B fine-tune of Qwen3-0.6B that rewrites one
raw ASR transcript as written text: fillers removed, self-corrections
resolved, punctuation and capitals applied, and numbers, dates, times,
currency and email addresses in written form. It is not speech-to-text and
"is not a chat model and will not follow general instructions" (model card).
The Q4_K_M GGUF is 462 MiB.

## Languages

English only. The card says: "This is release v1, and it covers English only."
Both repositories list `language: en`.

## Input format

The card requires an exact system prompt and a control line; "Skip either one,
change the system prompt's wording, or send values outside the trained sets,
and the model can hallucinate or produce garbled output."

System prompt (verbatim):

```
You are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text.
```

User message: a control line, a newline, then the transcript:

```
[Styling: <casual|semi-casual|semi-formal|formal>] [Structure: <prose|lists>] [Context: <general|email>]
<raw transcript>
```

`chat_template.jinja` is the stock Qwen3 template, which turns thinking on by
default. The card warns that without `enable_thinking=False` "you will usually
get no usable output at all". The literal prompt for raw completion endpoints
ends with the assistant prefix `<|im_start|>assistant\n<think>\n\n</think>\n\n`.

Output is plain text. `Structure: lists` may add Markdown `-` bullets and
`Context: email` adds blank lines between greeting, body and sign-off.
Filler-only input returns an empty string.

## Sampling

`generation_config.json` sets `"do_sample": false` (greedy). The GGUF card
says to pass temperature 0 on every request because the GGUF metadata carries
Qwen3's `temp = 0.6`, `top_p = 0.95`, `top_k = 20`. Size the output limit at
`1.3 × input_tokens + 32`; keep one pass under about 1,000 input tokens. The
GGUF card's Ollama Modelfile uses `num_ctx 4096`.

## License

`license: other`, `license_name: s1-mini-license`. The LICENSE file is the
Apache License 2.0 text, prefixed with:

> Copyright 2026 Superwhisper
>
> This model is a derivative work of Qwen3-0.6B, Copyright 2024 Alibaba Cloud,
> licensed under the Apache License, Version 2.0.

and followed by:

> ADDITIONAL TERM
>
> In addition to the terms of the Apache License, Version 2.0 above: any
> use, distribution, or integration of this model, whether unmodified or
> as part of a derivative work or product, must continue to identify it
> by its original name, "S1-mini" by "Superwhisper", using that exact
> capitalization, regardless of any other name under which the model or
> a product incorporating it is marketed or distributed.

NOTICE restates the additional term and says the LICENSE "is the operative text".

- **Commercial use:** allowed. Apache 2.0 section 2 grants a "perpetual,
  worldwide, non-exclusive, no-charge, royalty-free, irrevocable copyright
  license to reproduce, prepare Derivative Works of, publicly display, publicly
  perform, sublicense, and distribute". The card: "it can be embedded in
  open-source and commercial software alike: dictation apps, …".
- **Use inside another app:** allowed. The card: "You can use it in your own
  dictation app too, just check the license first."
- **Redistribution:** allowed under Apache 2.0 section 4: give recipients the
  license, mark modified files, keep notices, and include NOTICE attributions.
- **Attribution:** wherever it is used, call it "S1-mini" by "Superwhisper",
  with that exact capitalization.

BetterWispr does not bundle or redistribute the weights. The user downloads
them into Ollama with an explicit button. The app names the model
"S1-mini by Superwhisper" wherever it is offered and links the LICENSE.

## How BetterWispr uses it

- **Runtime:** the user's local Ollama server, so no new dependency. The
  button calls `POST /api/pull` with `hf.co/superwhisper/s1-mini-GGUF:Q4_K_M`,
  the build on which the card measured its accuracy. Hugging Face documents
  `hf.co/{user}/{repo}:{quant}` for Ollama.
- **Request:** `POST /api/generate` with `raw: true` and the card's literal
  prompt, including the empty think block, so the result does not depend on
  which template Ollama matches for the GGUF. `think: false` keeps Ollama's
  thinking parser off. Options: `temperature 0`, `num_ctx 4096`,
  `num_predict = characters × 13 / 30 + 32` (1.3 × a generous 3-characters-a-token
  guess, plus 32), stop at `<|im_end|>` and `<|endoftext|>`.
- **Control line:** `[Styling: semi-formal] [Structure: lists] [Context: general]`,
  with `Context: email` when the destination app is in the Email style
  context. Semi-formal is the card's suggested default and matches
  BetterWispr's Formal tone; the app's own tone (Casual, Very casual,
  Excited) is applied afterwards by `StyleFormatter`, the same as for the
  notes model. `lists` matches Medium's spoken-list formatting.
- **Vocabulary, screen context and mode instructions:** not sent. The input
  format has no field for them, and the card says any change to the prompt
  can garble the output. BetterWispr's own vocabulary replacements still run
  after S1-mini, as they do after every cleanup.
- **Reply handling:** strip any think tags and special tokens, then reuse
  `TranscriptPolisher.accepted`. An empty reply, a reply that adds new words
  or changes length too much, a timeout, Ollama not running or the model not
  installed all keep the Light text. There is no fallback to another model.
- **Limits:** English only (the same `TranscriptCleaner.isEnglish` check as
  Medium), at most 700 words a pass. A 2-minute dictation stays under the
  card's 1,000-token guidance, so there is no chunking.
- **Warm-up:** Ollama keeps a loaded model for 5 minutes by default, so 450 ms
  into a Medium recording BetterWispr sends an empty `generate` request with
  the same `num_ctx`, which loads S1-mini without generating text.

No accuracy claims are made here beyond the card's own figure (94.8% token
accuracy on 7,519 held-out English cases, Q4_K_M, greedy).
