"""AMB's CLI with tlon registered as a memory provider and ollama.com as answer model and judge.
Arguments are AMB's `run` flags, e.g. `run --dataset longmemeval --split s --memory tlon -q 20`."""

import json
import os
import sys
import time
import types
import urllib.error
import urllib.request
from pathlib import Path

AMB = Path(os.environ.get("AMB_DIR", Path.home() / ".cache/tlon-bench/amb"))
sys.path[:0] = [str(AMB / "src"), str(Path(__file__).resolve().parent)]

# AMB's provider registry imports every competitor at import time; tlon needs none of them.
class _Stub(types.ModuleType):
    def __getattr__(self, attr):
        return _Stub(attr)


for name in ("mem0", "qdrant_client", "sentence_transformers"):
    sys.modules[name] = _Stub(name)

os.environ.setdefault("GEMINI_API_KEY", "unused")  # AMB's CLI demands one even when Gemini is not used
# The published leaderboard answers with Gemini 3.1 Pro and judges with Gemini 2.5 Flash-Lite; these
# are the nearest plan-covered stand-ins (the strongest reasoner, and Google's small open model).
os.environ.setdefault("OMB_ANSWER_LLM", "ollama")
os.environ.setdefault("OMB_ANSWER_MODEL", "deepseek-v4-pro")
os.environ.setdefault("OMB_JUDGE_LLM", "ollama")
os.environ.setdefault("OMB_JUDGE_MODEL", "gemma4:31b")

from memory_bench import llm, memory  # noqa: E402
from memory_bench.llm.base import LLM  # noqa: E402
from tlon_provider import TlonProvider  # noqa: E402


def first_object(text):
    decoder = json.JSONDecoder()
    for i, ch in enumerate(text):
        if ch == "{":
            try:
                obj, _ = decoder.raw_decode(text, i)
                if isinstance(obj, dict):
                    return obj
            except json.JSONDecodeError:
                pass
    return None


class OllamaLLM(LLM):
    """ollama.com ignores both OpenAI json_schema and its own `format`, so the schema rides in
    the prompt and a reply missing a required key is retried."""

    def __init__(self, model="deepseek-v4.1-flash"):
        self._model = model

    @property
    def model_id(self):
        return f"ollama:{self._model}"

    def _chat(self, prompt):
        body = json.dumps({"model": self._model, "stream": False, "messages": [{"role": "user", "content": prompt}]})
        req = urllib.request.Request(
            "https://ollama.com/api/chat", data=body.encode(),
            headers={"Authorization": f"Bearer {os.environ['OLLAMA_API_KEY']}", "Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=300) as resp:
            return json.load(resp)["message"]["content"]

    def generate(self, prompt, schema):
        keys = ", ".join(f'"{k}" ({v.get("type", "string")})' for k, v in schema.properties.items())
        prompt = f"{prompt}\n\nRespond with ONLY a JSON object with exactly these keys: {keys}."
        last = None
        for attempt in range(5):
            try:
                text = self._chat(prompt)
                data = first_object(text)
                if data and all(k in data for k in schema.required):
                    return data
                last = f"bad shape: {text[:200]!r}"
            except (urllib.error.URLError, TimeoutError) as e:
                last = e
                time.sleep(5 * 2**attempt)
        raise RuntimeError(f"{self.model_id} gave no usable reply after 5 tries: {last}")


llm.REGISTRY["ollama"] = OllamaLLM
memory.REGISTRY["tlon"] = TlonProvider

from memory_bench.cli import app  # noqa: E402

app()
