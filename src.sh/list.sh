#!/bin/bash -eu

# List the Gemini models the API key can generate text with, one per line:
# the name to give chat.sh as GEMINI_MODEL, then its display name. Without
# billing on veltzer-gemini-id some of them (the Pro ones) refuse with a
# quota error. The API key is read as chat.sh reads it.

: "${GEMINI_PASS_KEY:=gcp/veltzer-gemini-id/api-key}"

key="$(pass show "${GEMINI_PASS_KEY}")"
key="${key%%$'\n'*}"
config="$(printf 'header = "x-goog-api-key: %s"' "${key}")"
out="$(curl --silent --show-error --config - --write-out '\n%{http_code}' "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000" <<< "${config}")"
status="${out##*$'\n'}"
body="${out%$'\n'*}"
if [[ "${status}" != 200 ]]
then
	message="$(jq --raw-output '.error.message // .' <<< "${body}" 2> /dev/null)" || message="${body}"
	echo "list.sh: HTTP ${status}: ${message}" >&2
	exit 1
fi
jq --raw-output '.models[]
	| select(.supportedGenerationMethods | index("generateContent"))
	| select(.name | startswith("models/gemini"))
	| "\(.name | ltrimstr("models/"))\t\(.displayName)"' <<< "${body}"
