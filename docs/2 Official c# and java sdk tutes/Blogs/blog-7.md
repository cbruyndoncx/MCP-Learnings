---
title: "Blog 7: Web Transports - Java's HTTP+SSE vs. C#'s ASP.NET Core Integration"
draft: false
---
## Blog 7: Web Transports - Java's HTTP+SSE vs. C#'s ASP.NET Core Integration

**Series:** Deep Dive into the Model Context Protocol SDKs (C# & Java)
**Post:** 7 of 10

Having explored the secure local channel provided by the [Stdio transport](blog-6.md) in our previous post, we now turn our attention to enabling Model Context Protocol (MCP) communication over the web using HTTP. This is essential for scenarios where the MCP client (e.g., a web application, a remote AI assistant) needs to interact with an MCP server hosted elsewhere, potentially across the internet or within a corporate network.

Both the C# and Java SDKs provide solutions for HTTP-based communication, but they exhibit significant differences in their primary approaches, reflecting both historical MCP specification versions and common framework patterns in their respective ecosystems.

This post examines:

1.  **Java SDK's HTTP+SSE Approach:** Its reliance on the dual-endpoint Server-Sent Events model and implementations for Servlets, Spring WebFlux, and Spring WebMvc.
2.  **C# SDK's ASP.NET Core Integration:** Its unified endpoint approach (`MapMcp`), likely implementing the newer Streamable HTTP specification, leveraging ASP.NET Core features.
3.  **Key Differences:** Single vs. Dual Endpoints, Session Management, Resumability, and Framework Integration.

### Java SDK: Embracing HTTP + Server-Sent Events (SSE)

The Java SDK's primary mechanism for web communication adheres closely to the **HTTP+SSE** transport model described in earlier versions of the MCP specification (like `2024-11-05`).

**The Dual-Endpoint Model:**

*   **SSE Endpoint (`GET`, e.g., `/sse`):**
    *   The client initiates a long-lived `GET` request here to establish the SSE connection.
    *   The server keeps this connection open, sending `text/event-stream` data.
    *   The *first* event sent by the server is the crucial `event: endpoint`, providing the URL (with a unique `sessionId`) for the client to send messages back *to* the server.
    *   Subsequent `event: message` events carry server-to-client JSON-RPC responses and notifications.
*   **Message Endpoint (`POST`, e.g., `/mcp/message?sessionId=...`):**
    *   The client sends its JSON-RPC requests and notifications to this endpoint via standard HTTP `POST` requests.
    *   The `sessionId` query parameter (obtained from the `endpoint` event) is essential for the server to route the incoming message to the correct client session (and its associated SSE connection).
    *   The server typically responds with `202 Accepted` immediately, sending the actual JSON-RPC response (if any) back asynchronously over the client's specific SSE connection.

**Implementations:**

The Java SDK provides several `McpServerTransportProvider` implementations catering to different Java web environments:

1.  **`HttpServletSseServerTransportProvider` (`mcp/` module):**
    *   Uses the standard Jakarta Servlet API (specifically async servlets).
    *   Suitable for traditional Servlet containers like Tomcat, Jetty, Undertow.
    *   Manages SSE connections using `jakarta.servlet.AsyncContext`.
    *   Requires manual setup (e.g., registering the provider as a Servlet).
    *   See `HttpServletSseServerTransportProviderIntegrationTests.java` for testing examples.

2.  **`WebFluxSseServerTransportProvider` (`mcp-spring-webflux/` module):**
    *   Built for reactive Spring applications using WebFlux.
    *   Uses `org.springframework.web.reactive.function.server.RouterFunction` to define the `/sse` (GET) and message (POST) routes.
    *   Leverages Project Reactor (`Flux`, `Mono`) and Spring's reactive SSE support (`ServerResponse.sse()`).
    *   Integrates naturally with Spring Boot WebFlux applications via `@Bean` configuration.

    ```java
    // Spring WebFlux Configuration Example
    @Configuration
    static class MyConfig {
        @Bean
        public WebFluxSseServerTransportProvider sseTransportProvider() {
            return new WebFluxSseServerTransportProvider(new ObjectMapper(), "/mcp/message");
        }

        @Bean
        public RouterFunction<?> mcpRouterFunction(WebFluxSseServerTransportProvider provider) {
            return provider.getRouterFunction(); // Provides GET /sse and POST /mcp/message
        }
        // ... other beans ...
    }
    ```

3.  **`WebMvcSseServerTransportProvider` (`mcp-spring-webmvc/` module):**
    *   Adapts the SSE model for traditional Spring MVC (Servlet-based) applications.
    *   Also provides a `RouterFunction` (using Spring MVC's functional endpoints introduced in Spring Framework 6) for easy integration.
    *   Internally likely uses Servlet async features similar to the `HttpServlet` provider but wrapped for Spring MVC.

**Client-Side (`HttpClientSseClientTransport` / `WebFluxSseClientTransport`):**

*   The clients handle connecting to the `/sse` endpoint, receiving the `endpoint` event, storing the message URL + session ID, listening for `message` events, and sending outgoing messages via `POST` to the correct URL.

**Key Java SSE Aspects:**

*   **Adherence to Older Spec:** Follows the dual-endpoint HTTP+SSE model.
*   **Framework Flexibility:** Provides implementations for standard Servlets, reactive Spring (WebFlux), and traditional Spring (WebMvc).
*   **Session Linking:** Relies entirely on the `sessionId` query parameter in POST requests to correlate client messages with the correct server-side SSE stream.
*   **No Built-in Resumability:** The protocol itself doesn't inherently support resuming a connection if the SSE stream drops.

### C# SDK: Unified Endpoint via ASP.NET Core Integration

The C# SDK takes a more modern approach, tightly integrating with ASP.NET Core and appearing to implement the newer **Streamable HTTP** transport specification (though it also includes handlers for legacy SSE compatibility).

**The Unified Endpoint Model (`MapMcp`):**

*   **Single Pattern (e.g., `/mcp`, or user-defined):** The `McpEndpointRouteBuilderExtensions.MapMcp(pattern)` method registers handlers for `GET`, `POST`, and `DELETE` verbs under a single route prefix.
*   **`StreamableHttpHandler` (`src/ModelContextProtocol.AspNetCore/StreamableHttpHandler.cs`):** This internal class seems to be the primary handler for requests mapped by `MapMcp`. It likely manages:
    *   **POST Requests:** Receiving client messages. It checks `Accept` headers (requiring both `application/json` and `text/event-stream`). It determines whether to respond with direct JSON or an SSE stream based on whether the incoming message(s) require responses. Handles session creation/validation using the `mcp-session-id` header.
    *   **GET Requests:** Handling requests for the *optional* standalone SSE stream for unsolicited server notifications. Requires `Accept: text/event-stream`. Manages only one GET stream per session. Includes logic for handling `Last-Event-ID` if resumability is configured.
    *   **DELETE Requests:** Handling explicit session termination requests from the client (validating `mcp-session-id`).
*   **Session Management (`HttpMcpSession`):** An internal class likely used by `StreamableHttpHandler` to represent and track active sessions (mapping session IDs to transports, user principals, activity timestamps). Stored in a `ConcurrentDictionary`.
*   **Transport (`StreamableHttpServerTransport`):** The underlying `ITransport` implementation used per-session, created *by* the `StreamableHttpHandler` when a new session starts via POST. It uses `IDuplexPipe` (likely from the `HttpContext`) for efficient request/response body streaming.
*   **Resumability:** While no explicit `EventStore` is visible in the *AspNetCore* project, the underlying `StreamableHttpServerTransport` in the core `ModelContextProtocol` project *does* support an `EventStore`. It's plausible this could be configured via DI if needed, enabling resumability.
*   **Idle Session Tracking (`IdleTrackingBackgroundService`):** An `IHostedService` periodically checks for inactive sessions (no active requests or GET stream) and disposes of them after a configurable timeout (`HttpServerTransportOptions.IdleTimeout`), preventing resource leaks.
*   **Legacy SSE Support (`SseHandler`):** The `MapMcp` extension *also* maps `/sse` (GET) and `/message` (POST) routes handled by `SseHandler.cs`. This provides backwards compatibility for older clients expecting the dual-endpoint setup.

**Example (ASP.NET Core `Program.cs`):**

```csharp
// C# ASP.NET Core Example
using ModelContextProtocol.Server; // For Tool/Prompt attributes
using Microsoft.AspNetCore.Builder; // For MapMcp
using Microsoft.Extensions.DependencyInjection; // For AddMcpServer/WithHttpTransport

var builder = WebApplication.CreateBuilder(args);

// 1. Configure MCP Server services & transport
builder.Services.AddMcpServer(options => {
        options.ServerInfo = new() { Name = "MyAspNetCoreMcpServer", Version = "1.0" };
    })
    .WithHttpTransport(httpOptions => { // Configure HTTP transport options
        httpOptions.IdleTimeout = TimeSpan.FromMinutes(30);
        // httpOptions.ConfigureSessionOptions = async (httpCtx, mcpOpts, ct) => { ... };
    })
    .WithToolsFromAssembly(); // Discover tools via attributes

var app = builder.Build();

// 2. Map MCP endpoints under the root ("/") path
// This registers handlers for GET/POST/DELETE on "/"
// AND handlers for GET /sse and POST /message for compatibility
app.MapMcp("/");

app.Run(); // Start the web server
```

**Key C# Aspects:**

*   **ASP.NET Core Native:** Deeply integrated with the standard web framework.
*   **Unified Endpoint:** Primarily uses the Streamable HTTP model with a single route pattern.
*   **Header-Based Session:** Uses the `Mcp-Session-Id` *header* for stateful sessions.
*   **Built-in Compatibility:** `MapMcp` includes handlers for the older SSE endpoints automatically.
*   **Potential Resumability:** The underlying transport supports `EventStore`, although not explicitly configured in basic examples.
*   **Robust Lifecycle:** Leverages `IHostedService` for tasks like idle session cleanup.

### Comparison: Web Transports

| Feature                  | Java (HTTP+SSE Providers)                  | C# (ASP.NET Core Integration)                | Notes                                                                                                                               |
| :----------------------- | :----------------------------------------- | :------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------- |
| **Primary Spec**         | HTTP+SSE (Dual Endpoint)                   | Streamable HTTP (Likely, Single Endpoint) + SSE Compat | C# aligns with the newer, more efficient spec. Java focuses on the older, widely understood SSE model.                            |
| **Endpoints**            | Separate GET `/sse`, POST `/message`         | Single pattern (`/mcp`) handles GET/POST/DELETE + Legacy Endpoints | C#'s unified approach simplifies routing configuration.                                                            |
| **Session Identification** | `sessionId` Query Parameter (POST)         | `Mcp-Session-Id` Header                      | Header usage is generally preferred over query parameters for session IDs.                                                          |
| **Framework Integration**| Specific Providers (Servlet, WebFlux, WebMvc) | Unified via `MapMcp` in ASP.NET Core         | C# offers a single integration point. Java requires choosing the provider matching the web framework.                           |
| **Resumability**         | No (Inherent in HTTP+SSE spec used)        | Yes (Potential via `EventStore` config)        | C#'s underlying transport supports it, giving it an edge for reliability. Java's SSE providers would need significant custom work. |
| **Configuration**        | Via `McpServer.async/sync` builders        | Via `AddMcpServer().WithHttpTransport()` DI extensions | Both offer configuration, but C# ties into the standard DI/Options patterns.                                                      |
| **Server Implementation**| `SseServerTransportProvider` subclasses    | `StreamableHttpHandler` / `SseHandler`       | Internal implementation details differ significantly based on the chosen spec and framework.                                      |

### End-User Impact: Reliability and Integration

The choice of web transport impacts the user experience, particularly for non-local interactions:

*   **Streamable HTTP (C#):**
    *   *Potentially More Efficient:* Fewer connections needed compared to classic SSE + POST.
    *   *More Resilient:* Built-in resumability means long-running operations (like complex tool calls with progress) are less likely to fail completely due to temporary network drops, providing a smoother UX.
    *   *Modern Standard:* Aligns with newer web practices.
*   **HTTP+SSE (Java):**
    *   *Widely Understood:* SSE is a mature technology.
    *   *Framework Support:* Good integration options across various Java web frameworks (Servlet, Spring).
    *   *Less Resilient (by default):* A dropped SSE connection usually means the client loses subsequent server messages until it reconnects, potentially missing progress updates or final results of long tasks without custom client/server logic.

### Conclusion

When taking MCP servers to the web, the C# and Java SDKs present different primary strategies. Java offers robust implementations of the classic HTTP+SSE transport, providing flexibility across Servlet, WebFlux, and WebMvc environments. C#, through its `ModelContextProtocol.AspNetCore` package, provides tight integration with ASP.NET Core, likely implementing the more modern and resilient Streamable HTTP protocol while thoughtfully including handlers for backwards compatibility with older SSE clients.

The C# approach, with its potential for built-in resumability and unified endpoint handling, appears more aligned with the latest MCP specification for web transports. However, Java's explicit support for various established web frameworks ensures broad applicability within the JVM ecosystem using the well-understood SSE model. Developers choosing between them should consider their target framework, the need for resumability, and their preference for framework integration style.

Our next post shifts focus back to security, examining **Blog 8: Authentication** approaches in the C# and Java SDKs.

---
