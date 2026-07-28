#!/usr/bin/env python3
"""Run an image-grounded OpenAI-compatible QC call without logging credentials."""

from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import re
import urllib.request

import yaml


def load_dotenv(path: Path) -> None:
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--prompt", type=Path, required=True)
    parser.add_argument("--max-tokens", type=int, default=7000)
    args = parser.parse_args()

    load_dotenv(Path.home() / ".hermes" / ".env")
    config = yaml.safe_load((Path.home() / ".hermes" / "config.yaml").read_text())
    provider = config["providers"][args.provider]
    match = re.fullmatch(r"\$\{([^}]+)\}", provider["api_key"])
    api_key = os.environ[match.group(1)] if match else provider["api_key"]
    encoded = base64.b64encode(args.image.read_bytes()).decode()
    body = {
        "model": args.model,
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": args.prompt.read_text()},
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/png;base64,{encoded}",
                            "detail": "high",
                        },
                    },
                ],
            }
        ],
        "max_tokens": args.max_tokens,
    }
    request = urllib.request.Request(
        provider["api"].rstrip("/") + "/chat/completions",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": "Bearer " + api_key,
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=300) as response:
        raw = response.read().decode(errors="replace")
    try:
        result = json.loads(raw)
    except json.JSONDecodeError:
        # Some OpenAI-compatible gateways reply as SSE even without stream=true.
        events = []
        for line in raw.splitlines():
            if not line.startswith("data:"):
                continue
            payload = line[5:].strip()
            if not payload or payload == "[DONE]":
                continue
            events.append(json.loads(payload))
        if not events:
            raise RuntimeError("Provider returned neither JSON nor parseable SSE")
        content_parts = []
        for event in events:
            event_choice = (event.get("choices") or [{}])[0]
            delta = event_choice.get("delta") or event_choice.get("message") or {}
            if delta.get("content"):
                content_parts.append(delta["content"])
        result = events[-1]
        result["choices"] = [
            {
                "message": {"content": "".join(content_parts)},
                "finish_reason": (events[-1].get("choices") or [{}])[0].get(
                    "finish_reason"
                ),
            }
        ]
    choice = (result.get("choices") or [{}])[0]
    print(choice.get("message", {}).get("content") or "")
    print("\n---ROUTE---")
    print(
        json.dumps(
            {
                "provider": args.provider,
                "requested_model": args.model,
                "returned_model": result.get("model"),
                "finish_reason": choice.get("finish_reason"),
                "usage": result.get("usage"),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
