"""tlon as an agent-memory-benchmark (AMB) memory provider: sessions go into a bench database
through bridge.exs, and retrieval is the server's own recall (see bridge.exs for the two modes)."""

import json
import os
import subprocess
import threading
from pathlib import Path

from memory_bench.memory.base import MemoryProvider
from memory_bench.models import Document

SERVER = Path(__file__).resolve().parents[2] / "server"
BRIDGE = Path(__file__).resolve().parent / "bridge.exs"
MARK = "@@TLON "


class TlonProvider(MemoryProvider):
    name = "tlon"
    description = "Tlön server recall over a bench database (TLON_BENCH_MODE=messages|facts)."
    kind = "local"

    def __init__(self):
        self._proc = None
        # One pipe to the bridge; the harness answers a question's queries concurrently.
        self._lock = threading.Lock()

    def _call(self, op, **req):
        with self._lock:
            if self._proc is None:
                env = {**os.environ, "TLON_DATABASE": os.environ.get("TLON_DATABASE", "tlon_bench")}
                self._proc = subprocess.Popen(
                    ["mix", "run", str(BRIDGE)], cwd=SERVER, env=env, text=True,
                    stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                )
            self._proc.stdin.write(json.dumps({"op": op, **req}) + "\n")
            self._proc.stdin.flush()
            for line in self._proc.stdout:
                if line.startswith(MARK):
                    reply = json.loads(line[len(MARK):])
                    if "error" in reply:
                        raise RuntimeError(f"tlon bridge {op}: {reply['error']}")
                    return reply
            raise RuntimeError(f"tlon bridge exited (code {self._proc.wait()}) during {op}")

    def cleanup(self):
        if self._proc:
            self._proc.stdin.close()
            self._proc.wait(timeout=30)
            self._proc = None

    def ingest(self, documents):
        docs = [
            {"id": d.id, "timestamp": d.timestamp, "messages": d.messages or json.loads(d.content)}
            for d in documents
        ]
        self._call("ingest", unit=documents[0].user_id, docs=docs)

    def retrieve(self, query, k=10, user_id=None, query_timestamp=None):
        reply = self._call("retrieve", query=query, k=k)
        return [Document(id=h["id"], content=h["text"], user_id=user_id) for h in reply["hits"]], reply
