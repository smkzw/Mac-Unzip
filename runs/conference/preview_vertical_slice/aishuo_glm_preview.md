Warning: Unknown toolsets: messaging, moa
# ArchiveWorkbench 架构预览审计 (Final Round)

本轮作为 conference loop 的最终回合，整合了前两轮的审计发现，通过对异步处理、并发安全和 UI 集成点的审视，对代码架构进行了最终挑战与定稿。以下是经过确认和校准的最终审计结论，供 Codex 处理。

---

## 1. 证据 (Evidence)
- **`ValidatedPreviewCacheURL.readData` (Lines 60-85)**: 读取逻辑循环结束后执行 `return nil` (第84行)，直接否定了成功的读取结果。
- **`ArchiveDocumentLoader.materializePreview`**: 在调用 `provider.materializeEntry` 之前未进行 `Task.isCancelled` 检查，不符合 Swift 并发取消建议。
- **`ArchiveWorkbenchAppDelegate` (Lines 6-13)**: 在 `applicationDidFinishLaunching` 和 `applicationWillTerminate` 中全局删除 `ValidatedPreviewCacheURL.cacheRoot`。
- **`PDFKitCanvas.makeNSView` & `updateNSView`**: 在同步环境内调度 `DispatchQueue.main.async` 更新可访问性标签，违反了 `NSViewRepresentable` 的同步更新原则。
- **`NativeVideoPreviewStateView`**: `AVPlayer` 在视图销毁时未显式处理暂停或销毁。

## 2. 推理 (Inference)
- **严重的逻辑阻塞**: `readData` 中的 bug 是决定性阻塞问题，导致除 fixture 外的所有生产预览读取均会判定为失败。
- **生命周期矛盾**: 应用级的全局清理与文件级的缓存验证机制存在冲突。预览数据应绑定至 `ArchiveDocumentLoader` 的会话生存周期，而非应用生命周期。
- **异步竞争**: `PDFKit` 可访问性更新的实现方式（异步）极易在快速滚动或视图刷新时触发竞争，导致辅助功能读取的数据与当前页面不一致。

## 3. 建议 (Recommendation)

### **Blockers (需立即修复)**
1.  **修正 `ValidatedPreviewCacheURL.readData`**: 修正逻辑流，删除第84行的 `return nil`，在循环成功退出后返回 `result`。
2.  **移除 `ArchiveWorkbenchAppDelegate` 的缓存清理逻辑**: 严禁在 `AppDelegate` 中进行全局缓存清理，应改为在 `ArchiveDocumentLoader` 的 `open` 方法开始时清理该会话对应的缓存子目录。

### **重要修复 (Essential Fixes)**
1.  **添加并发取消**: 在 `ArchiveDocumentLoader.materializePreview` 的核心 IO 调用之前添加 `try Task.checkCancellation()`。
2.  **清理 `PDFKitCanvas` 逻辑**: 将 `PDFKitCanvas` 的可访问性更新逻辑移出 `DispatchQueue.main.async`，整合到 `updateNSView` 的同步逻辑中，保持视图状态一致性。
3.  **完善视频资源管理**: 为 `NativeVideoPreviewStateView` 添加 `.onDisappear(perform: { player.pause() })` 以确保视图消失后视频停止流式传输。

### **可选改进 (Improvements)**
1.  **重构 `ArchiveDocumentLoader` 状态管理**: 将 `ArchiveDocumentLoader` 中的 `previewSessionURL` 移动至一个内部的 `SessionContext` 枚举，以显式处理会话打开、物化和重置的状态机。
2.  **提升 `PreviewRoutingPolicy` 效率**: 将该策略对象设为 `static` 或全局 `let` 实例，避免在 `loadSelectedPreview` 和 `preview` 渲染逻辑中频繁实例化。

## 4. 不确定性 (Uncertainty)
- `QLPreviewView` 在 Swift UI 中的 `NSViewRepresentable` 集成虽然通过 `revalidatedURL` 处理了潜在的文件路径篡改风险，但 QuickLook 框架在 `QLPreviewView` 内部如何处理缓存文件句柄属于系统黑盒，无法排除其内部存在未知的 IO 阻塞行为。

---

## 5. 对 Codex 的执行建议 (Actionable Path)
1. **优先修复 `readData`**: 这是系统预览功能的单一故障点。
2. **重构缓存清理**: 将缓存清理逻辑移入 `ArchiveDocumentLoader` 中，使其与 `ArchiveDocumentSnapshot` 的生命周期同步。
3. **增加自动化集成测试**: 在 `PreviewRoutingTests` 中增加一个针对 `MaterializePreview` 的并发取消测试用例，确保持续的切换操作不会导致大量文件句柄残留。
4. **验证修复**: 使用 Instruments 对 `ArchiveWorkbench` 进行内存与 CPU 采样，确保持久化会话时 `AVPlayer` 和 `QLPreviewView` 能够被正确释放。

*注：本结论经三次挑战后认定，已解决前序 round 中的逻辑漂移与认知局限，符合项目架构标准。*

↻ Resumed session 20260712_043103_352173 (2 user messages, 16 total messages)

session_id: 20260712_043103_352173
Exception ignored in: <coroutine object MCPServerTask.run at 0x10cc9f9c0>
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
Exception ignored in: <coroutine object MCPServerTask.run at 0x10cc9f880>
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
Exception ignored in: <coroutine object MCPServerTask.run at 0x10cc9f740>
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
