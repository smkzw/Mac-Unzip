Warning: Unknown toolsets: messaging, moa
API call failed after 3 retries: HTTP 503: No available channel for model Gemini-3.5-Flash under group default (distributor) (request id: 202607111821046972892898268d9d6O9erAcEz)


session_id: 20260712_022053_608561
Exception ignored in: <coroutine object MCPServerTask.run at 0x108cf1a80>
Traceback (most recent call last):
  File "/Users/smkzw/.hermes/hermes-agent/tools/mcp_tool.py", line 2783, in run
    parked = await self._wait_for_reconnect_or_shutdown(
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/smkzw/.hermes/hermes-agent/tools/mcp_tool.py", line 1997, in _wait_for_reconnect_or_shutdown
    t.cancel()
  File "/Users/smkzw/.local/share/uv/python/cpython-3.11.15-macos-aarch64-none/lib/python3.11/asyncio/base_events.py", line 762, in call_soon
    self._check_closed()
  File "/Users/smkzw/.local/share/uv/python/cpython-3.11.15-macos-aarch64-none/lib/python3.11/asyncio/base_events.py", line 520, in _check_closed
    raise RuntimeError('Event loop is closed')
RuntimeError: Event loop is closed
Exception ignored in: <coroutine object MCPServerTask.run at 0x108cf1940>
Traceback (most recent call last):
  File "/Users/smkzw/.hermes/hermes-agent/tools/mcp_tool.py", line 2783, in run
    parked = await self._wait_for_reconnect_or_shutdown(
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/smkzw/.hermes/hermes-agent/tools/mcp_tool.py", line 1997, in _wait_for_reconnect_or_shutdown
    t.cancel()
  File "/Users/smkzw/.local/share/uv/python/cpython-3.11.15-macos-aarch64-none/lib/python3.11/asyncio/base_events.py", line 762, in call_soon
    self._check_closed()
  File "/Users/smkzw/.local/share/uv/python/cpython-3.11.15-macos-aarch64-none/lib/python3.11/asyncio/base_events.py", line 520, in _check_closed
    raise RuntimeError('Event loop is closed')
RuntimeError: Event loop is closed
Exception ignored in: <coroutine object MCPServerTask.run at 0x108cf1800>
Traceback (most recent call last):
  File "/Users/smkzw/.hermes/hermes-agent/tools/mcp_tool.py", line 2783, in run
    parked = await self._wait_for_reconnect_or_shutdown(
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/smkzw/.hermes/hermes-agent/tools/mcp_tool.py", line 1997, in _wait_for_reconnect_or_shutdown
    t.cancel()
  File "/Users/smkzw/.local/share/uv/python/cpython-3.11.15-macos-aarch64-none/lib/python3.11/asyncio/base_events.py", line 762, in call_soon
    self._check_closed()
  File "/Users/smkzw/.local/share/uv/python/cpython-3.11.15-macos-aarch64-none/lib/python3.11/asyncio/base_events.py", line 520, in _check_closed
    raise RuntimeError('Event loop is closed')
RuntimeError: Event loop is closed
