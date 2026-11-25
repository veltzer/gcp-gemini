# gcp-gemini

Talk to Gemini from the command line, through the Gemini API with the API
key of the GCP project `veltzer-gemini-id`.

- `src.sh/chat.sh "question"` asks one question and prints the answer.
- `src.sh/chat.sh` with no arguments starts a conversation: each line you
  type is sent with everything said so far; an empty line or Ctrl-D ends it.
- `src.sh/list.sh` lists the models that can generate text.

The model is `gemini-3.5-flash` unless `GEMINI_MODEL` names another
(`GEMINI_MODEL=gemini-3.8-flash src.sh/chat.sh "..."`). The project has no
billing, so the API key is on the free tier: the Pro and Gemini 4 models
refuse with a quota error, and a busy model is retried a few times before
giving up.

Prerequisites: `curl`, `jq`, and pass(1) with the key at
`gcp/veltzer-gemini-id/api-key` (`GEMINI_PASS_KEY` names another entry).
The key is handed to curl on stdin, never on the command line or on disk.
