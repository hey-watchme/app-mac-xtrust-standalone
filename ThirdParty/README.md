# Third-Party Runtime Notes

This directory is reserved for local runtime notes and placement rules for
`whisper.cpp` and `llama.cpp`.

Do not commit:

- large model files
- downloaded runtime binaries
- local benchmark artifacts

Keep version notes and setup instructions here when sidecar integration starts.

## Development ASR note

The current Milestone 3 development path uses the Python `whisper` CLI if it
is installed locally.

This app does not auto-download the model at runtime.

Place the model file here before running ASR:

- `~/Library/Application Support/XTrust/com.xtrust.mac-local-first/models/whisper/small.pt`
