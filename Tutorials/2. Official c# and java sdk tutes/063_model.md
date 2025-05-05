Okay, here is a detailed draft for the next advanced blog post (effectively Blog 12), focusing on Notifications, Subscriptions, Error Handling, and Resilience across the four SDKs.

---

## Blog 12: Staying Synced & Handling Failures - Advanced Notifications, Subscriptions, and Resilience in MCP SDKs

**Series:** Deep Dive into the Model Context Protocol SDKs
**Post:** 12 of 10 (Advanced Topics)

Our journey through the Model Context Protocol (MCP) SDKs for TypeScript, Python, C#, and Java has taken us from [core concepts](link-to-post-1) to [advanced tooling](link-to-post-11) and [resource management](link-to-post-12). While request-response interactions form the backbone of MCP, truly dynamic and robust applications rely heavily on asynchronous communication (server-to-client notifications) and graceful handling of errors and interruptions.

For advanced developers building complex MCP integrations, mastering these aspects is crucial. This post dives into the nuances of:

1.  **Server-Sent Notifications:** How servers proactively push information (logs, updates, progress) to clients across the SDKs.
2.  **Client-Side Handling:** Comparing the mechanisms for receiving and reacting to these notifications.
3.  **Resource Subscriptions:** The lifecycle (`subscribe`/`unsubscribe`) and notification (`updated`) flow for keeping clients synced with resource changes.
4.  **Error Handling Strategies:** Differentiating and managing transport, protocol, and application-level errors.
5.  **Cancellation & Resilience:** Propagating cancellation signals and revisiting transport-level resilience mechanisms.

### Pushing Information: Server-Initiated Notifications

Beyond responding to requests, MCP servers can send notifications to inform clients about events or progress.

**Common Notification Types:**

*   **`notifications/message` (Logging):** Servers send log entries based on the level set by the client (`logging/setLevel` request).
*   **`notifications/{tools|resources|prompts}/list_changed`:** Sent when the server's available set of Tools, Resources, or Prompts changes (if the server supports this capability).
*   **`notifications/progress`:** Sent during long-running operations (initiated by a client request that included a `progressToken`) to provide status updates.
*   **`notifications/resources/updated`:** Sent to subscribed clients when a specific resource's content changes.

**Sending Notifications (Server-Side):**

*   **TypeScript (`McpServer`/`Server`):**
    *   Use methods on the `Server` instance (accessible via `mcpServer.server`): `server.sendLoggingMessage(...)`, `server.sendResourceUpdated(...)`, `server.sendToolListChanged(...)`, etc.
    *   Progress notifications are sent via the `sendNotification` function within the `RequestHandlerExtra` passed to tool/resource/prompt handlers: `extra.sendNotification({ method: "notifications/progress", params: { progressToken: ..., progress: ..., total: ... }})`.
    *   `list_changed` notifications are often sent *automatically* by `McpServer` when using the `.enable()`, `.disable()`, `.update()`, `.remove()` methods on registered handles.
*   **Python (`FastMCP`/`Server`):**
    *   Use methods on the injected `Context` object within `FastMCP` handlers: `ctx.log(...)`, `ctx.report_progress(...)`.
    *   For `list_changed` or `resource/updated`, use the underlying low-level server session: `ctx.session.send_resource_list_changed()`, `ctx.session.send_resource_updated(...)`. `FastMCP` itself doesn't provide high-level wrappers for these specific notifications currently.
*   **C# (`IMcpServer`):**
    *   Use extension methods on the `IMcpServer` instance (often injected into handlers): `server.SendNotificationAsync("notifications/message", logParams)`.
    *   Progress reporting uses the injected `IProgress<ProgressNotificationValue>` parameter in tool methods, which is automatically wired to send notifications if the client provided a token.
    *   `list_changed` requires manual sending via `server.SendNotificationAsync(...)` if not using a collection that raises events (like `McpServerPrimitiveCollection`).
*   **Java (`McpAsync/SyncServer` / `McpAsync/SyncServerExchange`):**
    *   Use methods on the `Exchange` object passed to handlers: `exchange.loggingNotification(...)`.
    *   Progress reporting is not automatically handled via an `IProgress` equivalent; requires manually calling `exchange.session.sendNotification("notifications/progress", ...)` with the correct token.
    *   `list_changed` and `resource/updated` require manual sending via `exchange.session.sendNotification(...)`.
    *   The `McpServerTransportProvider.notifyClients(...)` method allows broadcasting to *all* connected sessions (use with caution).

**Key Difference:** TypeScript's high-level `McpServer` provides the most automation for `list_changed` notifications. C# has good integration for `IProgress<>`. Python's `Context` offers convenient logging/progress methods. Java requires more manual notification construction/sending via the session object found within the `Exchange`.

### Listening In: Client-Side Notification Handling

Clients need to register handlers to react to these server-sent events.

*   **TypeScript (`Client.setNotificationHandler`):**
    *   Dynamically register handlers using a Zod schema and a callback.
    *   Allows multiple handlers per method.
    *   `fallbackNotificationHandler` catches unhandled types.
    ```typescript
    client.setNotificationHandler(LoggingMessageNotificationSchema, async (log) => { /*...*/ });
    ```
*   **Python (`ClientSession` Callbacks):**
    *   Specific callbacks (`logging_callback`, `toolsChangeConsumer`, etc.) are passed to the `ClientSession` *constructor* via the `McpClient.async/sync` builder.
    *   A generic `message_handler` catches anything else (including requests *from* the server like sampling/roots).
    ```python
    async def my_logger(params: LoggingMessageNotificationParams): # ...
    async def fallback(msg: Any): # ...

    client = McpClient.async(transport)
                .loggingConsumer(my_logger)
                .message_handler(fallback)
                .build()
    ```
*   **C# (`IMcpEndpoint.RegisterNotificationHandler`):**
    *   Registers handlers dynamically using the method name string and a `Func<JsonRpcNotification, CancellationToken, ValueTask>`.
    *   Returns an `IAsyncDisposable` to unregister the handler when disposed. Allows multiple handlers.
    ```csharp
    await using var reg = client.RegisterNotificationHandler(
        NotificationMethods.ResourceUpdatedNotification,
        async (notification, ct) => { /* Handle update */ }
    );
    ```
*   **Java (`McpClientSession` Configuration):**
    *   Handlers (`NotificationHandler`) are provided in a map to the internal `McpClientSession` constructor, typically populated via the `McpClient.async/sync` builder's consumer methods (e.g., `.loggingConsumer(...)`).
    *   Handlers are tied to the client instance lifetime.
    ```java
    // In McpClient.sync/async builder chain
    .loggingConsumer(notification -> { /* Handle log (Sync) */ })
    .toolsChangeConsumer(tools -> Mono.fromRunnable(() -> { /* Handle tools change (Async) */ }))
    ```

**Comparison:** C# and TypeScript offer more dynamic registration/unregistration of handlers using disposables. Python and Java configure handlers primarily at client creation time via the builder.

### Staying Updated: Resource Subscriptions

A specific notification flow enables clients to track resource changes:

1.  **Client Sends `resources/subscribe` Request:** Specifies the URI to watch.
2.  **Server:** If supported (requires `ResourcesCapability.Subscribe = true` and a registered `SubscribeToResourcesHandler`), the server registers the client's interest (often storing `(sessionId, uri)`).
3.  **Resource Change:** When the resource at the subscribed URI changes, the server detects this (implementation-specific).
4.  **Server Sends `notifications/resources/updated`:** Sends a notification containing the URI of the changed resource to *all* subscribed sessions.
5.  **Client:** Receives the notification (via its registered handler) and typically re-fetches the resource using `resources/read`.
6.  **Client Sends `resources/unsubscribe` Request:** When updates are no longer needed.
7.  **Server:** Removes the subscription registration.

**SDK Support:**

*   **High-Level:** None of the SDKs seem to offer a high-level client API like `client.subscribe(uri, callback)` out-of-the-box. Subscription management is manual.
*   **Server-Side Handlers:** C# and Java require explicitly registering handlers for `subscribe` and `unsubscribe` requests via the `IMcpServerBuilder` / `McpServer` builder if supporting this capability. TS and Python would likely require using the low-level `setRequestHandler` / `@server.request_handler` to handle these specific methods.
*   **State Management:** The *server* is responsible for tracking `(sessionId, uri)` subscription state, typically in memory (for single instances) or an external store (for scaled deployments).

### Handling the Unexpected: Errors and Resilience

Failures are inevitable in distributed systems. Robust MCP applications need to handle errors gracefully.

**Types of Errors:**

1.  **Transport Errors:** Network connection lost, process crashed (Stdio), HTTP errors (4xx/5xx), SSE stream disconnection.
    *   *Detection:* Usually manifest as exceptions from `transport.send/read` operations (e.g., `IOException`, `HttpRequestException`, `OperationCanceledException` on close).
    *   *Handling:* The core `Protocol`/`BaseSession` layers often catch these and trigger the `onerror` and/or `onclose` callbacks. Client applications typically need to implement reconnection logic (potentially using exponential backoff). Server transports might log the error and clean up the specific session.
2.  **Protocol Errors (JSON-RPC):** Malformed JSON (`ParseError`), invalid request structure (`InvalidRequest`), unknown method (`MethodNotFound`), invalid parameters (`InvalidParams`), internal server processing error (`InternalError`).
    *   *Detection:* SDKs perform validation. `McpSession`/`BaseSession` catches parsing/validation errors. Handlers might throw `McpError`/`McpException` with specific codes.
    *   *Handling:* SDKs generally convert these into `JSONRPCError` responses sent back to the original requester. Clients receive these as `McpError`/`McpException`.
3.  **Application Errors (Handler Exceptions):** Uncaught exceptions within Tool/Resource/Prompt handler logic.
    *   *Detection:* Caught by the SDK's request handling loop (`McpSession`/`BaseSession` or higher-level wrappers like `AIFunctionMcpServerTool`).
    *   *Handling:*
        *   *Tools:* C#, Python, and TS typically convert these into a `CallToolResult` with `isError: true` and the error message as text content. Java requires the handler to manually return such a result or risk an unhandled exception.
        *   *Resources/Prompts:* Usually result in a standard `JSONRPCError` response (often `InternalError`) being sent back to the client. The `raise_exceptions` flag in Python's low-level server can alter this for testing.

**Timeout Handling:**

*   Both client and server SDKs manage request timeouts (`requestTimeout` option).
*   If a response isn't received within the timeout, the pending request promise/future/Mono rejects with a specific timeout error (`McpError` with `RequestTimeout` code in TS, standard timeout exceptions in C#/Java).
*   TypeScript's `resetTimeoutOnProgress` offers fine-grained control for long-running tasks sending progress updates.

**Cancellation:**

*   **Client -> Server:** Clients pass `CancellationToken` (C#) or `AbortSignal` (TS) to request methods. If cancelled, the SDK sends `notifications/cancelled`.
*   **Server Handling:** The `RequestContext` (C#) / `RequestHandlerExtra` (TS) / `Exchange` (Java, via session) / `Context` (Python `FastMCP`) provides access to a cancellation signal/token tied to the request. Handlers *must* check this token periodically for long-running operations and abort gracefully.
*   **Server -> Client:** Less common, but a server could potentially cancel an operation it requested from a client (like `sampling/createMessage`) using a similar cancellation notification flow if needed.

**Resilience Revisited:**

*   **Streamable HTTP (TS/C#):** Offers the highest built-in resilience via `EventStore`. Missed *notifications and responses* during disconnects can be replayed automatically on reconnect if the client provides `Last-Event-ID`.
*   **HTTP+SSE (Java/Python):** No built-in transport-level replay. Resilience requires application-level strategies:
    *   Client retries for requests.
    *   Server storing task state externally and allowing clients to query status or retrieve final results after reconnection (missed intermediate progress/notifications are lost).
    *   Designing idempotent tools where possible.

### Conclusion: Building Robust Asynchronous Systems

Handling notifications, managing subscriptions, and gracefully recovering from errors and cancellations are hallmarks of advanced, production-ready MCP applications.

*   The SDKs provide varying levels of abstraction for sending and receiving standard **notifications**. TypeScript and C# offer more dynamic client-side handler registration, while Java and Python favor configuration-time setup.
*   **Resource subscriptions** require significant server-side state management, which is largely left to the developer in all current SDKs.
*   **Error handling** follows standard JSON-RPC patterns, with SDKs mapping errors to exceptions (`McpError`/`McpException`) or specific result types (`CallToolResult.isError`). Robust applications need `try/catch` blocks and appropriate logging.
*   **Cancellation** is supported via standard platform mechanisms (`CancellationToken`, `AbortSignal`) and requires cooperative handlers.
*   **Resilience** against network drops during web communication is most seamlessly handled by the **Streamable HTTP** transport's resumability feature (prominent in TS, likely available in C#), while **HTTP+SSE** (Java/Python) necessitates more application-level state management for recovery.

Mastering these asynchronous and resilience patterns is key to building MCP integrations that are not just functional but also reliable and user-friendly in the face of real-world complexities.

---