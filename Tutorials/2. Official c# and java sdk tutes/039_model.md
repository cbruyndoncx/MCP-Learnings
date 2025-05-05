Okay, here is a detailed draft for Blog Post 4, delving into the low-level server internals of the C# and Java MCP SDKs.

---

## Blog 4: Server Architecture - Under the Hood (MCP C# & Java Internals)

**Series:** Deep Dive into the Model Context Protocol SDKs (C# & Java)
**Post:** 4 of 10

In [Blog 3](link-to-post-3), we admired the convenience of the high-level server APIs offered by the C# and Java Model Context Protocol (MCP) SDKs. C#'s `IMcpServerBuilder` extensions and Java's `McpServer.sync/async` builders provide streamlined ways to configure servers using dependency injection or fluent patterns.

But what lies beneath these user-friendly facades? How does the SDK actually manage connections, route requests, handle notifications, and interact with the transport layer? Understanding these internals is key for advanced customization, debugging complex issues, or integrating MCP deeply into existing systems.

This post lifts the hood to explore the core server classes and session management logic:

*   **C# SDK:** Examining the internal `McpServer`, the role of `McpSession`, and the `ITransport` interface.
*   **Java SDK:** Unpacking the `McpAsync/SyncServer`, the central `McpServerSession`, and the `McpServerTransportProvider` pattern.
*   Comparing how each SDK handles request dispatch, context, and session lifecycles at this fundamental level.

### Why Look Under the Hood?

While the high-level APIs are often sufficient, exploring the internals offers:

1.  **Deeper Understanding:** See *how* the magic of the high-level APIs actually works.
2.  **Customization:** Identify extension points or base classes for building custom transports or specialized server behaviors.
3.  **Debugging:** Trace request flows more effectively when troubleshooting unexpected behavior.
4.  **Complex Integrations:** Understand how to wire MCP into applications where standard hosting models don't quite fit.

### C# SDK: DI, Sessions, and Transport Interaction

The C# SDK's low-level architecture is tightly integrated with .NET's hosting and DI patterns, even at its core.

**Key Components:**

1.  **`McpServer` (Internal Class - `src/.../Server/McpServer.cs`):**
    *   This is the concrete implementation behind the `IMcpServer` interface, often resolved via DI.
    *   It likely extends the internal `McpEndpoint` base class (shared client/server logic, analogous to `Protocol` in TS).
    *   **Responsibilities:** Holds configuration (`McpServerOptions`), manages the core `McpSession`, potentially coordinates with the hosting layer (`IHostedService`).
    *   **Handlers:** Stores registered request handlers (delegates) internally, likely in dictionaries keyed by method name (`RequestHandlers`). These are populated by the `IMcpServerBuilder` extensions or direct configuration. Similarly for `NotificationHandlers`.
2.  **`McpSession` (Internal Class - `src/.../Shared/McpSession.cs`):**
    *   Represents a *single* active MCP communication session over a specific transport.
    *   **Responsibilities:** Manages the lifecycle of a connection via an `ITransport`, handles JSON-RPC message framing, correlates requests and responses using IDs (`_pendingRequests`), dispatches incoming messages to the correct handlers stored in `McpServer`, manages cancellation tokens for requests (`_handlingRequests`).
    *   **`ProcessMessagesAsync`:** The core loop that reads from the transport's `MessageReader` channel and calls `HandleMessageAsync`.
    *   **`HandleMessageAsync`:** Determines message type (Request, Response, Notification) and routes it appropriately. For requests, it looks up the handler in `McpServer`'s collection and invokes it.
3.  **`ITransport` (`src/.../Protocol/Transport/ITransport.cs`):**
    *   The interface abstracting the communication channel (Stdio, HTTP Streamable/SSE, etc.).
    *   Provides `MessageReader` (a `ChannelReader<JsonRpcMessage>`) for the `McpSession` to consume incoming messages.
    *   Provides `SendMessageAsync(JsonRpcMessage, CancellationToken)` for the `McpSession` to send outgoing messages.
    *   Handles connection lifecycle (`DisposeAsync`).
4.  **`RequestContext<TParams>` (`src/.../Server/RequestContext.cs`):**
    *   A container passed to specific handler delegates (configured via builder extensions).
    *   Provides access to the `IMcpServer` instance, the specific request parameters (`TParams`), and crucially, the `IServiceProvider` (potentially scoped if `ScopeRequests` is true). This enables DI within handlers even when using the lower-level handler registration mechanisms.

**Conceptual Flow (Request):**

Transport (`ITransport`) receives raw data -> Parses into `JsonRpcMessage` -> Writes to `MessageReader` Channel -> `McpSession.ProcessMessagesAsync` reads from channel -> Calls `HandleMessageAsync` -> Identifies as Request -> Looks up handler in `McpServer.RequestHandlers` -> Invokes handler (potentially creating DI scope, passing `RequestContext`) -> Handler returns result -> `McpSession` sends `JsonRpcResponse` via `ITransport.SendMessageAsync`.

**Low-Level Configuration (Less Common):**

While typically done via `IMcpServerBuilder`, you could theoretically instantiate `McpServer` more directly (if its constructor were public or via internal access) and configure `McpServerOptions` with handler delegates manually:

```csharp
// Conceptual C# Low-Level Configuration (Illustrative)
var options = new McpServerOptions { /* ... server info, capabilities ... */ };

// Manually populate handler delegates in capabilities
options.Capabilities.Tools ??= new();
options.Capabilities.Tools.ListToolsHandler = async (requestContext, ct) => {
    // Access DI via requestContext.Services if needed
    // IMyToolService toolService = requestContext.Services.GetRequiredService<IMyToolService>();
    var tools = /* ... logic to get tools ... */;
    return new ListToolsResult { Tools = tools };
};
options.Capabilities.Tools.CallToolHandler = async (requestContext, ct) => {
    var toolName = requestContext.Params?.Name;
    var args = requestContext.Params?.Arguments;
    // ... find and execute tool logic ...
    // Use requestContext.Server.SendMessageAsync for notifications if needed
    return new CallToolResponse { /* ... */ };
};
// ... add other handlers similarly ...

// Create transport and server (DI usually handles this)
ITransport transport = new StdioServerTransport(options); // Or other transport
IMcpServer server = new McpServer(transport, options, loggerFactory, serviceProvider);

// Start the server's processing loop
await server.RunAsync();
```

This demonstrates that the core mechanism relies on populating the handler delegates within `McpServerOptions.Capabilities`.

### Java SDK: Transport Providers and Session Focus

The Java SDK employs a slightly different architectural pattern, notably the **Transport Provider** model for handling connections.

**Key Components:**

1.  **`McpServerTransportProvider` (`spec/McpServerTransportProvider.java`):**
    *   An *interface* responsible for *accepting* client connections and *creating* per-session transports.
    *   Implementations exist for Stdio, Servlets, WebFlux, WebMvc.
    *   **`setSessionFactory(McpServerSession.Factory)`:** This method is called by the `McpServer` during its setup. The provider stores this factory.
    *   When a new client connects (e.g., HTTP request arrives), the provider:
        *   Creates an appropriate `McpServerTransport` instance for that specific connection (e.g., `HttpServletMcpSessionTransport`, `WebFluxMcpSessionTransport`).
        *   Uses the stored `sessionFactory` to create a new `McpServerSession` linked to that transport.
    *   Also handles broadcasting notifications (`notifyClients`) and graceful shutdown (`closeGracefully`).
2.  **`McpServerTransport` (`spec/McpServerTransport.java`):**
    *   An *interface* representing the communication channel for a *single* client session.
    *   Implementations (like `StdioMcpSessionTransport`, `WebFluxMcpSessionTransport`) handle sending messages (`sendMessage`) for their specific session. Receiving is implicitly handled by routing incoming data (from the Provider) to the correct `McpServerSession`.
3.  **`McpServerSession` (`spec/McpServerSession.java`):**
    *   The core logic unit for managing *one* client connection. Analogous to C#'s internal `McpSession`.
    *   **Responsibilities:** Holds the `McpServerTransport` for its connection, handles incoming messages (`handle(JSONRPCMessage)`), correlates requests/responses (`pendingResponses`), manages request/notification handler dictionaries (`requestHandlers`, `notificationHandlers`), performs initialization handshake logic.
    *   It receives handler maps during construction (populated by the `McpAsync/SyncServer` builders).
4.  **`McpAsyncServer` / `McpSyncServer` (`server/`):**
    *   These are the public-facing server classes. They act more like **configurators and orchestrators** than the central processing unit.
    *   Their builders configure `McpServerFeatures` (containing handler lists/maps).
    *   When built, they primarily configure the `McpServerTransportProvider` by calling `setSessionFactory`, passing a factory that creates `McpServerSession` instances configured with the collected handlers. They don't directly handle individual messages in the same way C#'s `McpServer` does via its `McpSession`.
5.  **`McpAsync/SyncServerExchange` (`server/`):**
    *   Passed to the *user-defined* handler functions (provided in the `*Specification` objects to the builder).
    *   Provides access to the specific `McpServerSession` for that request, client capabilities/info, and convenience methods (`createMessage`, `listRoots`, `loggingNotification`). This is the primary way handlers interact with the MCP context.

**Conceptual Flow (Request):**

Network Listener (e.g., Tomcat, Netty) receives connection -> `McpServerTransportProvider` implementation accepts connection -> Creates `McpServerTransport` for the connection -> Calls `sessionFactory.create(transport)` -> Creates `McpServerSession` -> `McpServerSession` starts listening on its transport -> Transport receives raw data -> Parses to `JsonRpcMessage` -> Calls `McpServerSession.handle(message)` -> Session looks up handler in its `requestHandlers` map -> Invokes handler, passing an `Exchange` object -> Handler returns result -> Session sends `JsonRpcResponse` via its `McpServerTransport.sendMessage`.

**Low-Level Configuration:**

In Java, configuring the server involves creating the `McpServerFeatures` object (which holds the handler maps/lists) and passing it to the `McpAsync/SyncServer` constructor directly, bypassing the builder.

```java
// Conceptual Java Low-Level Configuration (Illustrative)
import io.modelcontextprotocol.server.*;
import io.modelcontextprotocol.server.transport.*;
import io.modelcontextprotocol.spec.*;
import io.modelcontextprotocol.spec.McpSchema.*;
import reactor.core.publisher.Mono;
import java.util.List;
import java.util.Map;
import com.fasterxml.jackson.databind.ObjectMapper;

// 1. Create Transport Provider
McpServerTransportProvider transportProvider = new StdioServerTransportProvider();

// 2. Define Handlers (as BiFunctions taking Exchange and Params)
BiFunction<McpAsyncServerExchange, Map<String, Object>, Mono<CallToolResult>> echoHandler =
    (exchange, args) -> Mono.just(new CallToolResult(
        List.of(new TextContent("Echo: " + args.get("message"))), false
    ));

BiFunction<McpAsyncServerExchange, ReadResourceRequest, Mono<ReadResourceResult>> resourceHandler =
    (exchange, req) -> Mono.just(new ReadResourceResult(
        List.of(new TextResourceContents(req.uri(), "text/plain", "Data for " + req.uri()))
    ));

// 3. Create Feature Specifications
Tool echoToolMeta = new Tool("echo", "Echoes", "{\"type\":\"object\", ...}");
AsyncToolSpecification echoToolSpec = new AsyncToolSpecification(echoToolMeta, echoHandler);

Resource configResourceMeta = new Resource("config://app", "Config", "app/json", null, null);
AsyncResourceSpecification configResourceSpec = new AsyncResourceSpecification(configResourceMeta, resourceHandler);

// 4. Create McpServerFeatures
McpServerFeatures.Async features = new McpServerFeatures.Async(
    new Implementation("LowLevelJavaServer", "0.9"),
    ServerCapabilities.builder().tools(true).resources(true, false).build(),
    List.of(echoToolSpec),                 // List of Tool Specs
    Map.of(configResourceMeta.uri(), configResourceSpec), // Map of Resource Specs
    List.of(),                             // List of Resource Templates
    Map.of(),                              // Map of Prompt Specs
    Map.of(),                              // Map of Completion Specs
    List.of(),                             // List of Root Change Handlers
    "Manual Server Instructions"
);

// 5. Instantiate the server directly
Duration timeout = Duration.ofSeconds(10);
ObjectMapper mapper = new ObjectMapper();
// Note: McpUriTemplateManagerFactory might be needed if using URI templates
McpAsyncServer lowLevelServer = new McpAsyncServer(transportProvider, mapper, features, timeout, null);

// 6. Run the server (often managed by the application host)
// transportProvider.setSessionFactory(...); // Implicitly done by McpAsyncServer constructor
// --> Start listening via the transport provider...
```

### Comparison: Server Internals

| Feature                  | C# SDK                                       | Java SDK                                              | Notes                                                                                                         |
| :----------------------- | :------------------------------------------- | :---------------------------------------------------- | :------------------------------------------------------------------------------------------------------------ |
| **Core Session Logic**   | `McpSession` (internal)                      | `McpServerSession`                                  | Manages a single client connection, request/response mapping, basic handlers.                               |
| **Connection Management**| `ITransport` (individual)                    | **`McpServerTransportProvider`** (accepts connections) | Java has an explicit provider layer for handling *new* connections and creating per-session transports.     |
| **Handler Storage**      | `RequestHandlers`/`NotificationHandlers` in `McpServer` | Handler Maps within `McpServerSession`             | Handlers are associated with the central server (C#) or the per-client session (Java).                        |
| **Handler Invocation**   | `McpSession` calls handler via `McpServer`   | `McpServerSession` calls handler directly           |                                                                                                               |
| **Context for Handlers** | `RequestContext` (includes `IServiceProvider`) | `McpAsync/SyncServerExchange` (includes `McpServerSession`) | Both provide request/session context. C# leans on DI; Java uses the explicit `Exchange` object parameter. |
| **Sync/Async**           | Unified `async`/`await` (`Task`)             | Explicit `McpAsyncServer`/`McpSyncServer` types       | Java makes the sync/async programming model choice explicit at the server class level.                    |
| **Hosting/Lifecycle**    | Integrates with `IHostedService`             | Relies on `McpServerTransportProvider` lifecycle      | C# lifecycle often tied to .NET Host; Java lifecycle depends on how the Provider is managed (e.g., Servlet container, Spring Boot). |

### Conclusion: Architecture Reflects Ecosystems

Delving into the low-level server internals reveals how each SDK adapts MCP concepts to its platform's strengths and conventions.

*   **C#** provides a unified `IMcpServer` experience heavily integrated with Dependency Injection. The `McpServer` acts as the central brain, configured via DI, while the internal `McpSession` manages the protocol details over an `ITransport`.
*   **Java** utilizes a Transport Provider pattern, clearly separating connection management (`McpServerTransportProvider`) from per-connection communication (`McpServerTransport` used by `McpServerSession`). The public `McpAsync/SyncServer` classes act primarily as configurators, setting up the handlers that the `McpServerSession` will invoke, passing an `Exchange` object for context.

Understanding these internal architectures is crucial for debugging, extending the SDKs, or integrating MCP into non-standard hosting environments. While the high-level APIs abstract much of this, the core session and transport logic ensures robust MCP communication under the hood.

With both client and server architectures explored, we'll next look at some of the **Advanced Capabilities** like dynamic updates, context injection, and CLI tooling in **Blog 9**.

---