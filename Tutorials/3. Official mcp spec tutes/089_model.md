Okay, here is a detailed draft for Blog Post 9 in the *new* advanced series structure, focusing on the essential utility features across the four MCP SDKs.

---

## Blog 9: Essential Utilities - Progress, Cancellation, Logging, & Pagination in MCP SDKs

**Series:** Deep Dive into the Model Context Protocol SDKs (Advanced Topics)
**Post:** 9 of 12

Beyond the core primitives of Tools, Resources, and Prompts, the Model Context Protocol (MCP) specification defines several essential **utility mechanisms** that enhance the robustness, usability, and observability of client-server interactions. These aren't standalone features but rather cross-cutting concerns integrated into the request/response and notification flows.

For advanced developers, understanding how the MCP SDKs implement these utilities – Progress Tracking, Request Cancellation, Structured Logging, and Result Pagination – is key to building responsive, resilient, and manageable applications. This post compares the implementation nuances across the TypeScript, Python, C#, and Java SDKs.

### 1. Progress Reporting (`notifications/progress`)

Long-running operations (often Tools, but potentially Resource reads) need a way to report status back to the requester without waiting for the final result.

*   **Specification (`docs/.../basic/utilities/progress.mdx`):**
    *   Requester includes an optional `progressToken` (unique string/number) in the request `_meta`.
    *   The handler (server for client requests, client for server requests like sampling) *may* send `notifications/progress` messages containing the original `progressToken`, a monotonically increasing `progress` value (number), an optional `total` (number), and an optional `message` (string).
*   **Implementation Insights:**
    *   **TypeScript (`Client.request` option):**
        *   Client provides an `onprogress: (prog: Progress) => void` callback in the `RequestOptions`.
        *   The `Client` automatically generates a unique `progressToken`, adds it to the outgoing request's `_meta`.
        *   It registers an internal handler for `notifications/progress`. When a notification with the matching token arrives, it extracts the `progress`, `total`, and `message` and calls the user's `onprogress` callback.
        *   Server-side handlers receive the `progressToken` via `RequestHandlerExtra._meta` and send notifications using `extra.sendNotification({...})`.
    *   **Python (`Context.report_progress` / `ProgressContext`):**
        *   Client side doesn't have a direct `onprogress` callback in `ClientSession.send_request`. Handling incoming progress notifications would likely require inspecting them in the general `message_handler`.
        *   Server-side (`FastMCP`): The `Context` object provides `ctx.report_progress(current, total, message)`. This checks if the *incoming* request (being handled by the current tool/resource function) had a `progressToken` in its `_meta` and, if so, uses `ctx.session.send_progress_notification(...)` to send the update. Python also offers a `shared/progress.py` utility `ProgressContext` for structured reporting.
    *   **C# (`IProgress<T>` Injection / `NotifyProgressAsync`):**
        *   Client-side (`McpClientExtensions.CallToolAsync`): Takes an optional `IProgress<ProgressNotificationValue> progress` argument. If provided, the client generates a token, adds it to the request, registers an internal handler for `notifications/progress`, and calls `progress.Report(...)` when updates arrive.
        *   Server-side (`McpServerTool`): If a tool method includes a parameter of type `IProgress<ProgressNotificationValue>`, the SDK (via `AIFunctionFactory`) automatically binds it. The handler calls `progress.Report(...)`. The SDK wrapper checks if the *incoming* request had a `progressToken` and wires the `IProgress<>.Report` call to send the `notifications/progress` message via `server.NotifyProgressAsync`. If no token was sent by the client, `Report` calls become no-ops (using `NullProgress.Instance`).
    *   **Java (Manual Sending / Handling):**
        *   Client-side: No direct `onprogress` callback in the builder or `sendRequest`. Requires manually registering a handler for `"notifications/progress"` using the builder's `.notificationHandler(...)` or session's `addNotificationHandler`.
        *   Server-side: The `Exchange` object doesn't have a dedicated progress method. Handlers must manually check `exchange.getRequest().params().meta().progressToken()` and call `exchange.getSession().sendNotification("notifications/progress", ...)` if a token exists.
*   **Comparison:** C# offers the most idiomatic integration using the standard `IProgress<T>` pattern. TypeScript's callback approach is clear and effective. Python provides server-side helpers via `Context`. Java requires the most manual implementation on both client and server for handling progress.

### 2. Request Cancellation (`notifications/cancelled`)

Provides a way for the sender of a request to signal that the result is no longer needed.

*   **Specification (`docs/.../basic/utilities/cancellation.mdx`):**
    *   Sender issues `notifications/cancelled` with the `requestId` of the original request.
    *   Receiver **SHOULD** stop processing and **MUST NOT** send a response. Receiver **MAY** ignore if already completed or uncancelable.
*   **Implementation Insights:**
    *   **Triggering Cancellation (Client -> Server):**
        *   TS: Pass an `AbortSignal` in `RequestOptions`. Calling `abort()` on the controller triggers sending the notification.
        *   Python: Pass an `anyio.CancelScope`? (Less explicit in docs). Relies on general async cancellation propagating. SDK likely sends notification on scope cancellation.
        *   C#: Pass a `CancellationToken` to request methods (e.g., `client.CallToolAsync(..., cancellationToken)`). Cancelling the token triggers sending the notification.
        *   Java: Use Reactor's cancellation mechanisms (`Mono.doOnCancel`, subscribing with a `Subscription` and calling `.cancel()`). The SDK likely hooks into this to send the notification.
    *   **Handling Cancellation (Server-Side Handler):**
        *   TS: `RequestHandlerExtra.signal` (`AbortSignal`). Handlers check `signal.aborted` or `signal.throwIfAborted()`.
        *   Python: `Context` doesn't directly expose the signal. Relies on `anyio` cancellation propagating up to the handler task (e.g., awaiting a cancelled operation).
        *   C#: `RequestContext<TParams>` contains `RequestAborted` (`CancellationToken`). Handlers receive/inject `CancellationToken` and check `IsCancellationRequested` / `ThrowIfCancellationRequested()`.
        *   Java: `McpAsync/SyncServerExchange` provides `getCancellationToken()`. Reactive handlers (`Mono`/`Flux`) should incorporate this or check `exchange.isCancelled()`.
    *   **Receiving Cancellation Notification:** All SDKs have internal handlers for `notifications/cancelled`. They look up the `requestId` in their map of in-flight operations (`_handlingRequests` in C#, `_in_flight` in Python, etc.) and trigger the associated cancellation mechanism (e.g., `CancellationTokenSource.Cancel()` in C#).
*   **Comparison:** All SDKs support the cancellation flow using platform-standard cancellation primitives (`AbortSignal`, `CancellationToken`, `CancelScope`, Reactor `Subscription`). C# and TS make accessing the cancellation signal/token very explicit within handlers.

### 3. Structured Logging (`logging/setLevel`, `notifications/message`)

Allows servers to send structured logs to interested clients, with clients controlling the verbosity.

*   **Specification (`docs/.../server/utilities/logging.mdx`):**
    *   Server declares `logging` capability.
    *   Client *may* send `logging/setLevel` request (`params: { level: LoggingLevel }`).
    *   Server sends `notifications/message` (`params: { level: LoggingLevel, logger?: string, data: unknown }`). Server **SHOULD** only send messages at or above the level set by the client (if any).
*   **Implementation Insights:**
    *   **Setting Level (Client):**
        *   TS: `client.setLoggingLevel(level)` extension method.
        *   Python: `session.set_logging_level(level)` method.
        *   C#: `client.SetLoggingLevel(level)` extension method.
        *   Java: `client.setLoggingLevel(level)` method (sync/async).
    *   **Handling Level Request (Server):**
        *   TS: Low-level `server.setRequestHandler(SetLevelRequestSchema, ...)`. `McpServer` doesn't handle automatically.
        *   Python: Low-level `@server.set_logging_level()` decorator. `FastMCP` doesn't handle automatically.
        *   C#: Optional `SetLoggingLevelHandler` in `LoggingCapability`. The core `McpServer` *always* tracks the last set level in its `LoggingLevel` property, regardless of handler registration.
        *   Java: Optional `setLevelHandler` in `McpServerFeatures`. The `McpServerSession` *always* tracks the level.
    *   **Sending Log Notification (Server):**
        *   TS: `server.sendLoggingMessage(params)`.
        *   Python: `ctx.log(level, message, ...)` helper in `FastMCP`. Low-level `session.send_log_message(level, data, logger)`.
        *   C#: `server.SendNotificationAsync(NotificationMethods.LoggingMessageNotification, params)`. `ILogger` integration via `AsClientLoggerProvider` extension.
        *   Java: `exchange.loggingNotification(params)` helper. Low-level `session.sendNotification(...)`.
    *   **Receiving Log Notification (Client):**
        *   TS: `client.setNotificationHandler(LoggingMessageNotificationSchema, ...)`.
        *   Python: `logging_callback` passed to `ClientSession`.
        *   C#: `client.RegisterNotificationHandler(NotificationMethods.LoggingMessageNotification, ...)`.
        *   Java: `.loggingConsumer(...)` on client builder.
*   **Comparison:** All SDKs support the basic flow. C# offers unique integration by providing an `ILoggerProvider` that automatically routes .NET `ILogger` messages over MCP. Server-side level handling requires explicit handlers in TS/Python but is implicitly tracked (though optionally handled) in C#/Java.

### 4. Pagination (`cursor`/`nextCursor`)

Handles large result sets for `list` operations (Tools, Resources, Prompts, Templates).

*   **Specification (`docs/.../server/utilities/pagination.mdx`):**
    *   Requests (`List*Request`) have optional `params.cursor` (opaque string).
    *   Responses (`List*Result`) have optional `nextCursor` (opaque string).
    *   Server determines page size. Client iterates by passing the received `nextCursor` as the `cursor` in the next request until `nextCursor` is null/absent.
*   **Implementation Insights:**
    *   **Client-Side:** All SDKs typically *abstract* pagination within their high-level `List*Async` (C#) or `list_*` (TS/Python/Java) methods/enumerables. These methods internally handle the loop of sending requests with cursors until `nextCursor` is null, accumulating or yielding results. Users usually get the full list or an async iterator without needing to manage cursors directly.
    *   **Server-Side:** The implementation burden falls entirely on the **developer writing the list handler**. The handler receives the `cursor` from the request parameters (via `RequestContext`/`Exchange`/`Extra`). It must:
        1.  Decode the cursor (if it contains state like an offset or last ID).
        2.  Fetch the appropriate page of data based on the cursor state.
        3.  Determine if more data exists beyond the current page.
        4.  Generate the *next* opaque `nextCursor` string (encoding the state needed to fetch the subsequent page).
        5.  Return the `List*Result` object containing the current page's items and the `nextCursor`.
*   **Comparison:** Client-side usage is generally simple across SDKs. Server-side implementation requires careful state management and cursor encoding/decoding logic, implemented manually by the developer within the handler function/delegate, regardless of the SDK.

### Conclusion: Building Beyond the Basics

The utility features of MCP – Progress, Cancellation, Logging, and Pagination – are essential for creating polished, resilient, and observable applications. While specified consistently, their implementation across the SDKs reveals different approaches to developer experience and integration:

*   **Progress:** C# (`IProgress<T>`) and TS (`onprogress` callback) offer the most idiomatic client-side handling. Python (`Context`) provides server-side helpers. Java requires more manual plumbing.
*   **Cancellation:** All SDKs integrate well with their platform's standard cancellation mechanisms (`CancellationToken`, `AbortSignal`, etc.) for both sending and receiving cancellations.
*   **Logging:** All SDKs support the basic flow. C# provides unique integration with `Microsoft.Extensions.Logging`.
*   **Pagination:** Clients benefit from automatic handling in list methods across SDKs. Server-side implementation remains a manual task for the handler developer in all ecosystems.

Mastering these utilities allows advanced developers to build MCP interactions that are not only functional but also provide crucial feedback during long operations, respond gracefully to interruptions, offer valuable observability, and handle large datasets efficiently.

---