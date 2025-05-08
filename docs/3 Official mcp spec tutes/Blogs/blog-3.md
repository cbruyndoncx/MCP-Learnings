---
title: "Blog 3: The Handshake - MCP Lifecycle and Capability Negotiation"
draft: false
---
## Blog 3: The Handshake - MCP Lifecycle and Capability Negotiation

**Series:** Deep Dive into the Model Context Protocol SDKs
**Post:** 3 of 12 (Advanced Topics)

Before any meaningful exchange of Tools, Resources, or Prompts can occur in the Model Context Protocol (MCP), the client and server must perform a crucial **initialization handshake**. This isn't just about establishing a connection; it's a formal negotiation defined by the [MCP specification](https://modelcontextprotocol.io/specification/draft/basic/lifecycle/) to ensure both parties speak the same protocol version and understand each other's capabilities.

This post dissects the `initialize` / `initialized` flow, focusing on how the TypeScript, Python, C#, and Java SDKs implement this critical lifecycle phase and manage the crucial **Capability Negotiation**. Understanding this handshake is vital for debugging connection issues, ensuring compatibility, and controlling the features available during an MCP session.

### The Initialization Sequence (MCP Spec Recap)

1.  **Client -> Server: `initialize` Request:**
    *   The *first* message sent by the client after the transport connection is established.
    *   **MUST** contain:
        *   `protocolVersion`: The *latest* MCP spec version the client supports (e.g., `"2025-03-26"`).
        *   `clientInfo`: An `Implementation` object (`{ name: string, version: string }`).
        *   `capabilities`: A `ClientCapabilities` object declaring what the client can do (e.g., handle `sampling/createMessage`, process `roots/list_changed` notifications).
    *   **MUST NOT** be part of a JSON-RPC batch.

2.  **Server -> Client: `initialize` Response (Result or Error):**
    *   **On Success (`result`):**
        *   `protocolVersion`: The version the server *chooses* to use for this session. This **MUST** be a version the server supports and **SHOULD** be the version the client requested if possible, otherwise the latest version the server *does* support.
        *   `serverInfo`: The server's `Implementation` object.
        *   `capabilities`: A `ServerCapabilities` object declaring what the *server* can do (e.g., supports `tools`, `resources` with `subscribe`, `prompts` with `listChanged`, `logging`).
        *   `instructions` (Optional): Human-readable hints for using the server.
    *   **On Error (`error`):** If the server cannot proceed (e.g., unsupported client `protocolVersion`, invalid request), it sends a standard JSON-RPC error response.

3.  **Client Validation:** The client receives the `initialize` response.
    *   It **MUST** check if it supports the `protocolVersion` chosen by the server. If not, it **SHOULD** disconnect.
    *   It stores the server's `capabilities` and `serverInfo`.

4.  **Client -> Server: `initialized` Notification:**
    *   If the client accepts the server's response, it sends this parameter-less notification.
    *   Signals that the client is ready for normal operation using the negotiated version and capabilities.

5.  **Session Active:** Both sides can now send any requests/notifications allowed by the negotiated capabilities.

### SDK Implementations of the Handshake

How do the SDKs orchestrate this dance?

**1. TypeScript (`Client.connect` / `Server` handler):**

*   **Client (`Client.connect`):**
    *   Called *after* `new Client(...)`.
    *   Takes a `Transport` instance.
    *   Internally calls `transport.start()`.
    *   *Automatically* sends the `initialize` request using `ClientInfo` and `Capabilities` provided during `Client` construction (or defaults).
    *   Waits for the server's response using the core `Protocol.request` logic.
    *   *Validates* the returned `protocolVersion` against `SUPPORTED_PROTOCOL_VERSIONS`. Throws an error and closes the transport if incompatible.
    *   Stores `serverInfo`, `serverCapabilities`, `serverInstructions` on the `Client` instance.
    *   *Automatically* sends the `initialized` notification.
    *   Resolves the `connect` promise upon successful completion.
*   **Server (`Server` internal handler):**
    *   The low-level `Server` has a built-in handler for the `initialize` method (registered in its constructor).
    *   This handler (`_oninitialize` in `src/server/index.ts`) receives the `InitializeRequest`.
    *   It stores the `clientInfo` and `clientCapabilities` on the `Server` instance.
    *   It determines the best compatible `protocolVersion` to use.
    *   It constructs the `InitializeResult` using its own `ServerInfo` and `Capabilities` (provided during `Server` construction or via `McpServer` configuration).
    *   The core `Protocol` layer sends the response back.
    *   It also has a handler for `initialized` notification which triggers the optional `oninitialized` callback.

**2. Python (`ClientSession.__aenter__` / `ServerSession` handler):**

*   **Client (`ClientSession.__aenter__` / `initialize()`):**
    *   The `async with ClientSession(...)` context manager automatically calls `session.initialize()` upon entering the block.
    *   `initialize()` sends the `initialize` request using `client_info` and capabilities derived from constructor arguments (e.g., presence of `sampling_callback`).
    *   It waits for the response, validates the `protocolVersion` against `SUPPORTED_PROTOCOL_VERSIONS`, raises `RuntimeError` on mismatch.
    *   Stores server info/capabilities internally (less explicitly exposed via properties than TS client).
    *   Sends the `initialized` notification.
    *   Returns the `InitializeResult` object.
*   **Server (`ServerSession` internal handler):**
    *   The internal `_received_request` method within `ServerSession` specifically checks if the request method is `initialize`.
    *   If it is, it marks the session state as `Initializing`, stores the `client_params` (including capabilities and info), and constructs the `InitializeResult` based on the `InitializationOptions` passed when the `ServerSession` was created by the `Server`.
    *   It sends the response.
    *   The internal `_received_notification` method checks for `InitializedNotification` and updates the session state to `Initialized`, allowing subsequent requests/notifications.

**3. C# (`McpClientFactory.CreateAsync` / `McpServer` handler):**

*   **Client (`McpClientFactory.CreateAsync`):**
    *   This factory method orchestrates the entire connection and initialization.
    *   It takes an `IClientTransport`.
    *   Calls `transport.ConnectAsync()` to get an `ITransport`.
    *   Creates the internal `McpClient`/`McpSession`.
    *   *Automatically* sends the `initialize` request using `McpClientOptions` (passed to the factory).
    *   Waits for the response, validates `protocolVersion`. Throws `McpException` or `TimeoutException`.
    *   Stores server details (`ServerInfo`, `ServerCapabilities`, `ServerInstructions`) on the `IMcpClient` instance.
    *   *Automatically* sends the `initialized` notification.
    *   Returns the fully connected and initialized `IMcpClient`.
*   **Server (`McpServer` internal handler):**
    *   Similar to TS, the internal `McpServer` sets up a handler for `initialize` (`SetInitializeHandler`).
    *   Receives the request, stores client info/caps.
    *   Determines response `protocolVersion`.
    *   Constructs `InitializeResult` using configured `McpServerOptions` (often populated via DI builder extensions).
    *   Sends the response.
    *   Handles `initialized` notification internally.

**4. Java (`client.initialize()` / `McpServerSession` handler):**

*   **Client (`McpAsync/SyncClient.initialize()`):**
    *   *Explicitly* called by the developer *after* the client object is built (`McpClient.async/sync(...).build()`).
    *   Sends the `initialize` request using `clientInfo` and `capabilities` configured via the builder.
    *   Waits for the response (blocking in Sync, returning `Mono<InitializeResult>` in Async).
    *   Validates `protocolVersion`. Throws `McpError` on mismatch or other errors.
    *   Stores server details internally.
    *   Sends the `initialized` notification.
    *   Returns the `InitializeResult` object.
*   **Server (`McpServerSession` internal handler):**
    *   The `handle(JSONRPCMessage)` method within `McpServerSession` checks for `InitializeRequest`.
    *   It performs state checks (must be first request), stores `clientCapabilities`/`clientInfo`, validates version, constructs `InitializeResult` based on the `McpServerFeatures` it was created with, and sends the response via its dedicated `McpServerTransport`.
    *   It also handles the `InitializedNotification` to transition its internal state.

### Capability Negotiation in Practice

The `capabilities` objects exchanged during initialization are crucial dictionaries telling each side what the *other* side supports.

*   **Client Declares:** Support for `sampling`, `roots` (and `roots.listChanged`).
*   **Server Declares:** Support for `tools`, `resources`, `prompts` (and their respective `listChanged` flags), `resources.subscribe`, `logging`, `completions` (newer specs).

**How SDKs Use Negotiated Capabilities:**

*   **Client-Side Checks:** Before sending a request like `tools/call`, a well-behaved client SDK *should* check if the stored `serverCapabilities` actually includes `tools`.
    *   *TS/Python:* The `enforceStrictCapabilities` option controls whether the base `Protocol`/`BaseSession` throws an error if a capability is missing on the *server* side before sending.
    *   *C#/Java:* This check seems less explicit in the core client methods; developers might need to check `client.ServerCapabilities` manually before calling certain methods if strict adherence is required.
*   **Server-Side Checks:** Before sending a request like `sampling/createMessage`, the server SDK *should* check if the stored `clientCapabilities` includes `sampling`.
    *   *TS/Python:* `enforceStrictCapabilities` also controls checks for missing *client* capabilities before the server sends a request.
    *   *C#/Java:* The `IMcpServer` interface includes `ClientCapabilities` property. Server logic (especially within Tools/Prompts needing sampling or roots) should check this property. `McpServerExtensions` like `AsSamplingChatClient` (C#) perform this check internally.

**Nuance:** While the spec defines capabilities, ensuring SDKs *consistently* and *correctly* check them before *all* relevant operations can be challenging. The `enforceStrictCapabilities` flag in TS/Python acknowledges that older or simpler implementations might not perfectly advertise or check capabilities, offering a compatibility mode. C#/Java appear to rely more on developers performing explicit checks where needed.

### Error Handling during Handshake

*   **Version Mismatch:** Server responds with its version, client disconnects if incompatible.
*   **Invalid Initialize Request:** Server sends `JSONRPCError` (e.g., code `-32600 Invalid Request`).
*   **Timeout:** Client or server times out waiting for `initialize` response or `initialized` notification (SDKs typically have specific `InitializationTimeout` settings).
*   **Transport Failure:** Underlying transport fails during handshake (e.g., process fails to start in Stdio, HTTP connection error).

### Conclusion: The Foundation of Trust

The MCP initialization handshake is more than just establishing a connection; it's a critical negotiation that sets the stage for the entire session. It ensures both client and server agree on the protocol version and are aware of each other's capabilities.

All four SDKs implement this lifecycle faithfully, albeit with slightly different orchestration:

*   **TypeScript and C#** largely automate the handshake within their `connect`/`CreateAsync` methods.
*   **Python and Java** require an explicit `initialize()` call after creating the client session object.

Understanding how capabilities are declared (DI/Attributes in C#, Builder/Options in TS/Java/Python) and how they are checked (explicitly by developers or implicitly by the SDK with flags like `enforceStrictCapabilities`) is vital for advanced users building interoperable and robust MCP applications. This handshake ensures that subsequent interactions only use features that both parties have agreed to support, forming the foundation of trust for the complex operations MCP enables.

Next, we'll dive back into the server internals, specifically focusing on how requests are dispatched to the correct handlers once the session is active.

---
