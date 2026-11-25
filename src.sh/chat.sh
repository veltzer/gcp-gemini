#!/bin/bash -eu

# Talk to Gemini. With arguments, asks them as one prompt and prints the
# answer. Without, starts a conversation: each line you type is sent with
# everything said so far; an empty line or end of input (Ctrl-D) ends it.
#
# It uses the Gemini API (generativelanguage.googleapis.com) with the API key
# of the GCP project veltzer-gemini-id. The key lives in pass(1) and is handed
# to curl on stdin as a config line, so it never appears in a process listing
# or on disk.
#
# Environment:
#   GEMINI_MODEL     the model to talk to (default below: the newest flash
#                    model that answers reliably on the free tier, chosen
#                    2026-11-25; gemini-3.8-flash is newer but was mostly
#                    overloaded); list.sh lists them
#   GEMINI_PASS_KEY  the pass(1) entry holding the API key

: "${GEMINI_MODEL:=gemini-3.5-flash}"
: "${GEMINI_PASS_KEY:=gcp/veltzer-gemini-id/api-key}"
gemini_api="https://generativelanguage.googleapis.com/v1beta"
# the conversation so far, as the generateContent "contents" array
gemini_contents="[]"

# gemini_curl URL [CURL ARGS...]: one call to the API, the key from pass.
# Sets gemini_status (the HTTP status) and gemini_body (the response).
gemini_curl() {
	local url="${1}"
	shift
	local key
	key="$(pass show "${GEMINI_PASS_KEY}")"
	key="${key%%$'\n'*}"
	local config
	config="$(printf 'header = "x-goog-api-key: %s"' "${key}")"
	local out
	out="$(curl --silent --show-error --config - --write-out '\n%{http_code}' "${@}" "${url}" <<< "${config}")"
	gemini_status="${out##*$'\n'}"
	gemini_body="${out%$'\n'*}"
}

# gemini_error WHO: prints the API's error message for the last call.
gemini_error() {
	local message
	message="$(jq --raw-output '.error.message // .' <<< "${gemini_body}" 2> /dev/null)" || message="${gemini_body}"
	echo "${1}: HTTP ${gemini_status}: ${message}" >&2
}

# gemini_generate CONTENTS_JSON: sends a conversation (the generateContent
# "contents" array) to GEMINI_MODEL. Sets gemini_ok to true and gemini_answer
# to the reply's text, or gemini_ok to false after saying why on stderr.
# Retries a few times while the model is overloaded (503) or rate limited
# (429), which the free tier often is.
gemini_generate() {
	local request
	request="$(jq --compact-output --null-input --argjson contents "${1}" '{contents: $contents}')"
	gemini_ok=false
	gemini_answer=""
	local attempt
	for attempt in 1 2 3 4 5
	do
		gemini_curl "${gemini_api}/models/${GEMINI_MODEL}:generateContent" \
			--header 'Content-Type: application/json' --data "${request}"
		case "${gemini_status}" in
			200)
				gemini_answer="$(jq --raw-output '[.candidates[0].content.parts[]? | select(.thought != true) | .text // empty] | join("")' <<< "${gemini_body}")"
				gemini_ok=true
				return 0
				;;
			429|500|503)
				echo "gemini: ${GEMINI_MODEL} busy (HTTP ${gemini_status}), try ${attempt} of 5" >&2
				sleep $((attempt * 5))
				;;
			*)
				break
				;;
		esac
	done
	gemini_error gemini
}

# gemini_say TEXT: says TEXT to the model as the next turn of the
# conversation and prints the answer. On success both turns join
# gemini_contents; on failure the conversation stays as it was, so the same
# text can be tried again. Sets gemini_ok to true or false.
gemini_say() {
	local asked
	asked="$(jq --compact-output --arg text "${1}" '. + [{role: "user", parts: [{text: $text}]}]' <<< "${gemini_contents}")"
	gemini_generate "${asked}"
	if [[ "${gemini_ok}" != true ]]
	then
		return 0
	fi
	printf '%s\n' "${gemini_answer}"
	gemini_contents="$(jq --compact-output --arg text "${gemini_answer}" '. + [{role: "model", parts: [{text: $text}]}]' <<< "${asked}")"
}

if [[ "$#" -gt 0 ]]
then
	gemini_say "$*"
	if [[ "${gemini_ok}" != true ]]
	then
		exit 1
	fi
	exit 0
fi

echo "chatting with ${GEMINI_MODEL}; an empty line or Ctrl-D ends" >&2
while IFS= read -r -e -p "> " line && [[ -n "${line}" ]]
do
	gemini_say "${line}"
done
