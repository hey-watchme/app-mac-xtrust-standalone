#!/usr/bin/env python3
"""
Usage: python3 moonshine_transcribe.py <audio_file> <output_dir> <model_dir>

Transcribes 16kHz mono WAV using Moonshine Base JA via sherpa-onnx.
Writes transcript to <output_dir>/<audio_basename>.txt.
"""
import sys
import os
import re
import wave
import numpy as np
import sherpa_onnx

SAMPLE_RATE = 16000
MAX_SAMPLES = int(8.5 * SAMPLE_RATE)  # Safety limit for ONNX 10-second constraint

_CJK_SPACE_RE = re.compile(
    r'(?<=[　-鿿豈-﫿぀-ゟ゠-ヿ＀-￯])'
    r' '
    r'(?=[　-鿿豈-﫿぀-ゟ゠-ヿ＀-￯])'
)


def clean_text(text):
    return _CJK_SPACE_RE.sub('', text).strip()


def read_wav_float32(path):
    with wave.open(path, 'rb') as wf:
        assert wf.getnchannels() == 1, f"Expected mono, got {wf.getnchannels()} channels"
        assert wf.getsampwidth() == 2, "Expected 16-bit PCM"
        sample_rate = wf.getframerate()
        raw = wf.readframes(wf.getnframes())
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    return samples, sample_rate


def make_recognizer(model_dir):
    return sherpa_onnx.OfflineRecognizer.from_moonshine_v2(
        encoder=os.path.join(model_dir, "encoder_model.ort"),
        decoder=os.path.join(model_dir, "decoder_model_merged.ort"),
        tokens=os.path.join(model_dir, "tokens.txt"),
        num_threads=4,
    )


def transcribe_chunk(recognizer, samples):
    if len(samples) == 0:
        return ""
    stream = recognizer.create_stream()
    stream.accept_waveform(SAMPLE_RATE, samples)
    recognizer.decode_stream(stream)
    return clean_text(stream.result.text)


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <audio_file> <output_dir> <model_dir>", file=sys.stderr)
        sys.exit(1)

    audio_path, output_dir, model_dir = sys.argv[1], sys.argv[2], sys.argv[3]

    for f in ["encoder_model.ort", "decoder_model_merged.ort", "tokens.txt"]:
        p = os.path.join(model_dir, f)
        if not os.path.exists(p):
            print(f"Missing model file: {p}", file=sys.stderr)
            sys.exit(2)

    samples, sample_rate = read_wav_float32(audio_path)
    if sample_rate != SAMPLE_RATE:
        print(f"Expected {SAMPLE_RATE}Hz, got {sample_rate}Hz", file=sys.stderr)
        sys.exit(3)

    recognizer = make_recognizer(model_dir)

    if len(samples) <= MAX_SAMPLES:
        result = transcribe_chunk(recognizer, samples)
    else:
        overlap = int(0.9 * SAMPLE_RATE)
        parts = []
        start = 0
        while start < len(samples):
            end = min(start + MAX_SAMPLES, len(samples))
            parts.append(transcribe_chunk(recognizer, samples[start:end]))
            if end >= len(samples):
                break
            start = end - overlap
        result = "".join(parts)

    audio_name = os.path.splitext(os.path.basename(audio_path))[0]
    output_path = os.path.join(output_dir, f"{audio_name}.txt")
    os.makedirs(output_dir, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(result)
    print(result)


if __name__ == "__main__":
    main()
