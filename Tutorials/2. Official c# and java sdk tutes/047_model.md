Okay, here's a detailed draft for Blog Post 8 in the C#/Java series, focusing on framework integration. *Note: Since Blog 7 covered the transports which are inherently tied to frameworks, this post will reiterate some transport points but focus more on the *how* of integration (DI, hosting, routing) rather than the *what* (protocol mechanics).*

---

## Blog 8: Framework Integration - ASP.NET Core (C#) vs. Spring/Servlets (Java)

**Series:** Deep Dive into the Model Context Protocol SDKs (C# & Java)
**Post:** 8 of 10

Throughout this series comparing the C# and Java Model Context Protocol (MCP) SDKs, we've seen how foundational choices in language and libraries shape the developer experience. Nowhere is this more apparent than in how the SDKs integrate with the dominant web application frameworks in their respective ecosystems: **ASP.NET Core** for C#/.NET and **Spring (WebFlux/WebMvc) / Jakarta Servlets** for Java.

While [Blog 7](link-to-post-7) focused on the specifics of the HTTP transports (Streamable HTTP vs. HTTP+SSE), this post examines *how* developers wire the MCP server logic into these frameworks. We'll explore:

*   **C# SDK:** Seamless integration using `Microsoft.Extensions.DependencyInjection`, `IHostedService`, and ASP.NET Core routing extensions (`MapMcp`).
*   **Java SDK:** Dedicated modules for Spring WebFlux and WebMvc, plus a provider for standard Jakarta Servlets, leveraging framework-specific patterns.
*   How these integrations impact configuration, service lifecycles, request handling, and dependency injection.

### C# SDK: Native ASP.NET Core / Generic Host Integration

The C# SDK is designed from the ground up to feel like a natural extension of the modern .NET application hosting model. Integration is typically achieved in `Program.cs` (or `Startup.cs` in older styles).

**Key Integration Points:**

1.  **Dependency Injection (`IServiceCollection`):**
    *   **`AddMcpServer()`:** This is the starting point. It registers core services needed by the MCP server (like `McpServerOptions`, internal handlers, potentially the `McpServer` itself) into the standard .NET DI container.
    *   **`IMcpServerBuilder` Extensions:** Methods like `WithTools<T>()`, `WithPromptsFromAssembly()`, `WithListResourcesHandler(...)` primarily work by configuring `McpServerOptions` or registering specific handler implementations or `McpServerTool`/`McpServerPrompt` instances within the DI container.
    *   **Tool/Prompt Dependencies:** Because tools and prompts are often resolved *from* the DI container (especially when using attribute discovery or `WithTools<T>`), they can directly request other registered application services (like `DbContext`, `HttpClient`, custom business logic services) via constructor injection.

2.  **Hosting (`IHostedService`):**
    *   **`WithStdioServerTransport()`:** Registers the `StdioServerTransport` *and* the `SingleSessionMcpServerHostedService`. When the .NET host starts (`app.RunAsync()`), this hosted service automatically retrieves the `IMcpServer` and `ITransport` from DI and starts the server's message processing loop (`server.RunAsync()`). It handles graceful shutdown linked to the host lifetime.
    *   **`WithHttpTransport()`:** Registers services needed by the ASP.NET Core integration (`StreamableHttpHandler`, `SseHandler`, `IdleTrackingBackgroundService`). It does *not* register a service to automatically call `IMcpServer.RunAsync()`, as the request handling is driven by incoming HTTP requests mapped via `MapMcp`. The `IdleTrackingBackgroundService` runs alongside the web host to clean up inactive sessions.

3.  **Routing (ASP.NET Core - `IEndpointRouteBuilder`):**
    *   **`MapMcp(pattern)`:** This extension method (from `ModelContextProtocol.AspNetCore`) is the key piece for web hosting. It registers the necessary endpoints within the ASP.NET Core routing system.
    *   Internally, it maps the specified route `pattern` (e.g., `/mcp`) to the internal `StreamableHttpHandler` for `GET`, `POST`, and `DELETE` methods.
    *   It *also* maps the legacy `/sse` (GET) and `/message` (POST) routes to the `SseHandler` for backwards compatibility.
    *   It leverages ASP.NET Core's built-in features like request/response streaming, header handling, and potentially authentication/authorization middleware applied to the mapped routes.

**Example (`Program.cs` Snippet):**

```csharp
// C# ASP.NET Core Integration
var builder = WebApplication.CreateBuilder(args);

// Configure standard ASP.NET Core services (logging, config, etc.)
builder.Services.AddHttpClient(); // Example dependency

// Configure MCP Server via DI
builder.Services.AddMcpServer(options => {
    options.ServerInfo = new() { Name = "MyWebAppServer", Version = "1.0" };
})
    .WithHttpTransport(httpOptions => { // Configures ASP.NET Core handlers
        httpOptions.IdleTimeout = TimeSpan.FromMinutes(30);
    })
    .WithTools<MyWebServiceTools>(); // Register tools (can use DI)

var app = builder.Build();

// Add standard ASP.NET Core middleware (auth, CORS, etc.)
// app.UseAuthentication();
// app.UseAuthorization();

// Map MCP endpoints (e.g., to "/mcp")
app.MapMcp("/mcp");

// Run the web application host
app.Run();

// Tool class potentially using DI
[McpServerToolType]
public class MyWebServiceTools(HttpClient httpClient, ILogger<MyWebServiceTools> logger)
{
    [McpServerTool]
    public async Task<string> FetchData(string url)
    {
        logger.LogInformation("Fetching data from {Url}", url);
        return await httpClient.GetStringAsync(url);
    }
}
```

**Summary (C#):** Integration is seamless and idiomatic for .NET developers, leveraging standard DI, Hosting, and ASP.NET Core patterns. Configuration is centralized through `IServiceCollection` extensions.

### Java SDK: Adapters for Spring and Servlets

The Java SDK provides specific adapter modules to bridge MCP communication with common Java web frameworks, primarily focusing on the HTTP+SSE transport model.

**Key Integration Points:**

1.  **Transport Providers:** Instead of direct hosting integration, the Java SDK uses the `McpServerTransportProvider` pattern. You choose the provider that matches your web framework.
2.  **`WebFluxSseServerTransportProvider` (`mcp-spring-webflux/`):**
    *   **Target:** Reactive Spring applications using WebFlux.
    *   **Mechanism:** Provides a `getRouterFunction()` method. This returns a Spring WebFlux `RouterFunction` that defines the `GET /sse` and `POST /message` routes.
    *   **Integration:** You register this `RouterFunction` as a `@Bean` in your Spring configuration. WebFlux handles the incoming HTTP requests and routes them to the provider's internal handlers.
    *   **Internals:** Uses `ServerResponse.sse()` to create the SSE stream and handles POST bodies using WebFlux request handling (`request.bodyToMono(String.class)`).

    ```java
    // Java Spring WebFlux Configuration
    import org.springframework.context.annotation.Bean;
    import org.springframework.context.annotation.Configuration;
    import org.springframework.web.reactive.function.server.RouterFunction;
    import org.springframework.web.reactive.function.server.ServerResponse;
    import io.modelcontextprotocol.server.transport.WebFluxSseServerTransportProvider;
    // ... other imports

    @Configuration
    public class McpConfig {

        @Bean
        public WebFluxSseServerTransportProvider mcpTransportProvider(ObjectMapper objectMapper) {
            // Assumes ObjectMapper bean exists
            return new WebFluxSseServerTransportProvider(objectMapper, "/mcp/message");
        }

        @Bean
        public RouterFunction<ServerResponse> mcpRoutes(WebFluxSseServerTransportProvider provider) {
            // Integrates MCP routes into the WebFlux routing system
            return provider.getRouterFunction();
        }

        @Bean
        public McpAsyncServer mcpServer(WebFluxSseServerTransportProvider provider /*, other dependencies */) {
            McpAsyncServer server = McpServer.async(provider)
                .serverInfo("MyWebFluxServer", "1.0")
                // .tools(...) - Tools might need manual wiring or Spring component scanning
                // .resources(...)
                // .prompts(...)
                .build();
            // The server logic is configured, but WebFlux handles the HTTP requests
            return server;
        }
    }
    ```

3.  **`WebMvcSseServerTransportProvider` (`mcp-spring-webmvc/`):**
    *   **Target:** Traditional Spring applications using Spring MVC (Servlet-based).
    *   **Mechanism:** Also provides `getRouterFunction()` using Spring MVC's *functional* routing support (available since Spring Framework 6). This defines the same `/sse` and `/message` routes but uses Servlet API primitives underneath (likely async servlets for SSE).
    *   **Integration:** Register the `RouterFunction` as a `@Bean`. Spring MVC's `DispatcherServlet` routes requests appropriately.

4.  **`HttpServletSseServerTransportProvider` (`mcp/` core module):**
    *   **Target:** Generic Jakarta Servlet containers (Tomcat, Jetty, etc.) *without* Spring MVC.
    *   **Mechanism:** Implements the `jakarta.servlet.http.HttpServlet`.
    *   **Integration:** You must manually register this class as a Servlet in your `web.xml` or using Servlet container-specific configuration, mapping it to the desired URL patterns (one for `/sse`, one for `/message`). It uses `request.startAsync()` for handling SSE connections.

**Dependency Injection (Java):**

*   The core Java SDK builder doesn't have direct integration with a DI framework like Spring (unlike C#'s builder).
*   When using the Spring modules (`mcp-spring-*`), you typically register your Tool/Resource/Prompt handler implementations as Spring `@Component`s or `@Service`s.
*   You would then manually create the `Async/SyncToolSpecification` (etc.) objects, likely within a Spring `@Configuration` class, retrieving the handler bean instances from the Spring context and passing them to the specification constructor before adding them to the `McpServer` builder.

```java
// Conceptual Java Spring DI for Handlers
@Service
public class MyToolHandler { // Your actual tool logic bean
    private final MyDependency dep;
    public MyToolHandler(MyDependency dep) { this.dep = dep; }

    public CallToolResult handleEcho(McpSyncServerExchange exchange, Map<String, Object> args) {
        // use this.dep
        return new CallToolResult(List.of(new TextContent("Echo " + args.get("msg"))), false);
    }
}

@Configuration
public class McpServerConfiguration {
    @Bean
    public McpSyncServer mcpServer(
        McpServerTransportProvider transportProvider,
        MyToolHandler myToolHandler // Inject the handler bean
    ) {
        Tool echoToolMeta = new Tool("echo", "...", "{}");
        // Manually create spec, passing the handler bean's method reference
        SyncToolSpecification echoSpec = new SyncToolSpecification(
            echoToolMeta,
            myToolHandler::handleEcho // Use method reference from injected bean
        );

        return McpServer.sync(transportProvider)
            // ... other config ...
            .tools(echoSpec)
            .build();
    }
    // ... other beans (TransportProvider, MyDependency) ...
}
```

### Comparison: Framework Integration

| Feature                   | C# (ASP.NET Core)                        | Java (Spring/Servlet)                           | Notes                                                                                                  |
| :------------------------ | :--------------------------------------- | :---------------------------------------------- | :----------------------------------------------------------------------------------------------------- |
| **Primary Mechanism**     | DI Extensions + Middleware (`MapMcp`)      | Transport Providers + Framework Adapters        | C# feels more "built-in" to the host; Java uses adapter providers for specific frameworks.              |
| **Web Transport Setup**   | Single `.WithHttpTransport().MapMcp()`   | Choose Provider + Register Routes/Servlet     | C# setup is simpler for web. Java requires selecting the correct provider for WebFlux/WebMvc/Servlet. |
| **Handler DI**            | Native via DI container (constructor/method) | Manual wiring in `@Configuration` common        | C# leverages DI more directly for injecting dependencies *into* handlers/tools.                       |
| **Lifecycle Management**  | `IHostedService` integration             | Depends on Provider/Framework (e.g., Servlet destroy, Spring context close) | Both integrate with standard platform lifecycles.                                                      |
| **Flexibility**           | Tied to ASP.NET Core / Generic Host      | Adapters for Servlet, WebFlux, WebMvc           | Java offers more explicit choices for different Java web stacks via separate providers.                |
| **HTTP Spec Compliance**  | Likely Streamable HTTP + SSE Compat      | HTTP+SSE                                      | C# likely follows the newer spec via its unified handler.                                              |

### Conclusion: Idiomatic Integration is Key

Both SDKs achieve successful integration with their platform's dominant web frameworks, but through different means.

*   **C#** offers a highly streamlined experience for developers already using ASP.NET Core or the Generic Host. `AddMcpServer`, the builder extensions, and `MapMcp` provide a cohesive way to configure and launch an MCP server, leveraging familiar DI and hosting patterns. The likely implementation of Streamable HTTP provides modern transport benefits.
*   **Java** provides targeted solutions for the diverse Java web landscape with dedicated modules for Spring WebFlux, Spring WebMvc, and standard Servlets. While requiring the developer to choose the correct provider and perform more manual wiring (especially for DI into handlers), it offers clear integration paths for each major environment, primarily using the well-established HTTP+SSE transport model.

The choice again reflects the ecosystems: .NET's more unified hosting and DI model lends itself to the extension method approach, while Java's diverse framework landscape benefits from specific adapter modules built upon a core provider pattern. Both successfully enable developers to embed MCP server functionality within their existing web applications.

With client/server architecture and transports covered, the final posts will tackle **Advanced Capabilities (Blog 9)** and provide a **Synthesis and Future Outlook (Blog 10)**.