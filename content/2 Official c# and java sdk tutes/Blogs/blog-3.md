---
title: "Blog 3: Server APIs - Building Blocks (.NET DI vs. Java Builders)"
draft: false
---
## Blog 3: Server APIs - Building Blocks (.NET DI vs. Java Builders)

**Series:** Deep Dive into the Model Context Protocol SDKs (C# & Java)
**Post:** 3 of 10

In [Blog 2](blog-2.md), we examined the foundational data contracts – the MCP schemas defined using C# POCOs with `System.Text.Json` and Java POJOs with Jackson. These schemas ensure clients and servers speak the same language. But how do developers *construct* a server application using these SDKs?

While the [low-level server APIs](blog-4.md) (which we'll cover next) offer fine-grained control, both the C# and Java SDKs provide higher-level mechanisms designed to simplify server setup and configuration. These APIs handle boilerplate like registering protocol handlers, integrating with transports, and managing server capabilities.

This post compares the primary approaches for building and configuring MCP servers in each SDK:

*   **C# SDK:** Leveraging the ubiquitous **`Microsoft.Extensions.DependencyInjection`** pattern with `IMcpServerBuilder` extension methods.
*   **Java SDK:** Employing a fluent **Builder pattern** via static methods on the `McpServer` class (`McpServer.sync(...)`, `McpServer.async(...)`).

### C#: Fluent Configuration via Dependency Injection Extensions

The C# SDK deeply integrates with the standard .NET dependency injection (DI) and hosting abstractions (`Microsoft.Extensions.DependencyInjection`, `Microsoft.Extensions.Hosting`). Configuring an MCP server feels idiomatic for developers familiar with ASP.NET Core or generic host applications.

**The Core Pattern:**

1.  **`AddMcpServer()`:** An extension method on `IServiceCollection` that registers the essential MCP server services and returns an `IMcpServerBuilder`.
2.  **`IMcpServerBuilder` Extensions:** A series of extension methods (`.WithTools<T>()`, `.WithPrompts<T>()`, `.WithStdioServerTransport()`, `.WithHttpTransport()`, `.WithListResourcesHandler()`, etc.) are chained onto the builder to configure server features, handlers, and transports.
3.  **Attribute-Based Discovery:** Many extensions (like `.WithToolsFromAssembly()`, `.WithPrompts<T>()`) use reflection to find classes and methods marked with specific attributes (`[McpServerToolType]`, `[McpServerTool]`, `[McpServerPromptType]`, `[McpServerPrompt]`) and register them automatically.
4.  **Hosting Integration:** The configured services are often used with `Microsoft.Extensions.Hosting` to run the server, e.g., as a background service (`SingleSessionMcpServerHostedService` for Stdio) or integrated into an ASP.NET Core application (`MapMcp`).

**Example (Stdio Server with Hosting):**

```csharp
// Program.cs (Simplified from samples/TestServerWithHosting)
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using ModelContextProtocol.Server;
using System.ComponentModel;

var builder = Host.CreateApplicationBuilder(args);

// 1. Add MCP Server services and get the builder
builder.Services.AddMcpServer(options => {
        // Configure basic McpServerOptions directly
        options.ServerInfo = new() { Name = "MyDotNetServer", Version = "1.1" };
        options.ServerInstructions = "Use this server for echo and AI sampling.";
    })
    // 2. Configure Stdio Transport
    .WithStdioServerTransport()
    // 3. Discover and register tools/prompts via attributes
    .WithToolsFromAssembly() // Scans current assembly
    .WithPromptsFromAssembly(); // Scans current assembly

// (Optional: Add other services needed by tools/prompts to DI)
// builder.Services.AddHttpClient(...);

var app = builder.Build();
await app.RunAsync(); // Runs the IHostedService managing the MCP server

// --- Tool Definition (in same or different file) ---
[McpServerToolType] // Mark class for discovery
public static class MyTools
{
    [McpServerTool, Description("Echoes the message.")]
    public static string Echo(string message) => $"Echo: {message}";

    // Method parameters like IMcpServer or services from DI
    // are automatically injected if registered.
    [McpServerTool]
    public static async Task<string> UseAi(IMcpServer server, HttpClient http, string query)
    {
        // Use injected server context and HttpClient
        var response = await server.RequestSamplingAsync(/* ... */);
        return response.Content.Text ?? "";
    }
}
```

**Example (ASP.NET Core Server):**

```csharp
// Program.cs (Simplified from samples/AspNetCoreSseServer)
var builder = WebApplication.CreateBuilder(args);

// 1. Add MCP Server & Configure Features
builder.Services.AddMcpServer()
    .WithHttpTransport() // Configures necessary handlers for MapMcp
    .WithTools<EchoTool>() // Register specific tool types
    .WithTools<SampleLlmTool>();

var app = builder.Build();

// 2. Map MCP endpoints (e.g., /mcp, /sse, /message)
app.MapMcp();

app.Run(); // Runs the ASP.NET Core host
```

**Key C# Aspects:**

*   **DI-Centric:** Configuration is tied to the `IServiceCollection`. Tools and prompts can easily receive dependencies via constructor or method injection.
*   **Fluent Builder Extensions:** Provides a discoverable and chainable configuration API.
*   **Attribute Discovery:** Simplifies registration for tools and prompts defined within classes.
*   **Hosting Integration:** Seamlessly integrates with standard .NET application hosting models.

### Java: Explicit Builder Pattern

The Java SDK uses a more traditional Builder pattern, accessed via static factory methods on the `McpServer` class. It distinguishes explicitly between synchronous and asynchronous server configurations from the start.

**The Core Pattern:**

1.  **`McpServer.sync(provider)` / `McpServer.async(provider)`:** Static methods initiate the builder, requiring an `McpServerTransportProvider` instance upfront.
2.  **Builder Methods:** Chain methods like `.serverInfo(...)`, `.capabilities(...)`, `.tools(...)`, `.resources(...)`, `.prompts(...)`, `.requestTimeout(...)` on the returned `SyncSpecification` or `AsyncSpecification` object.
3.  **Handler Registration:** Methods like `.tools(...)` typically accept lists or maps of "Specification" objects (e.g., `AsyncToolSpecification`, `SyncResourceSpecification`). These specifications pair the metadata (like `Tool` or `Resource` objects) with the corresponding handler `Function` or `BiFunction`.
4.  **`.build()`:** Finalizes the configuration and returns the configured `McpSyncServer` or `McpAsyncServer` instance.
5.  **Running:** The transport provider often needs separate integration (e.g., providing a router function for Spring WebFlux, using a Servlet for WebMvc, or manual stream handling for Stdio). The server logic itself doesn't automatically "run" just from building; it depends on the transport provider's lifecycle.

**Example (Async Stdio Server):**

```java
// Java Example (Conceptual - requires transport setup)
import io.modelcontextprotocol.server.*;
import io.modelcontextprotocol.server.transport.*;
import io.modelcontextprotocol.spec.*;
import io.modelcontextprotocol.spec.McpSchema.*;
import reactor.core.publisher.Mono;
import java.util.List;
import java.util.Map;
// ... other imports

// 1. Create Transport Provider
McpServerTransportProvider transportProvider = new StdioServerTransportProvider();

// Define a tool specification
Tool echoToolMeta = new Tool("echo", "Echoes input", /* schema */ "{\"type\":\"object\",...}");
AsyncToolSpecification echoToolSpec = new AsyncToolSpecification(
    echoToolMeta,
    (exchange, args) -> Mono.just(new CallToolResult(
        List.of(new TextContent("Echo: " + args.get("message"))), false
    ))
);

// Define a resource specification
Resource configResourceMeta = new Resource("config://app", "App Config", "application/json", null, null);
AsyncResourceSpecification configResourceSpec = new AsyncResourceSpecification(
    configResourceMeta,
    (exchange, req) -> Mono.just(new ReadResourceResult(
        List.of(new TextResourceContents(req.uri(), "application/json", "{\"theme\":\"dark\"}"))
    ))
);

// 2. Start builder chain
McpAsyncServer server = McpServer.async(transportProvider)
    // 3. Configure via builder methods
    .serverInfo("MyJavaServer", "1.0")
    .instructions("Instructions for Java server.")
    .capabilities(ServerCapabilities.builder().tools(true).resources(true, false).build()) // Explicit capabilities
    .tools(echoToolSpec) // Pass specification objects
    .resources(Map.of(configResourceMeta.uri(), configResourceSpec)) // Can use maps
    // ... other configurations (.prompts, .requestTimeout) ...
    // 4. Build the server logic object
    .build();

// 5. Running depends on the transport provider
// For Stdio, you might manually start the session handling loop if not using hosting
// (The SDK's tests and samples often wrap this)
// transportProvider.setSessionFactory(... server logic using session...);
// --> Start listening on System.in/out via the provider...
```

**Key Java Aspects:**

*   **Builder Pattern:** Classic Java pattern for object construction and configuration.
*   **Explicit Sync/Async:** Separate builder entry points (`McpServer.sync`/`.async`) lead to distinct server types.
*   **Handler Specifications:** Requires wrapping handler functions along with metadata into `*Specification` objects before passing them to the builder.
*   **Transport Provider:** Server creation is tied to a specific `McpServerTransportProvider` instance from the start.
*   **Framework Integration:** Less built-in core integration; relies on specific modules (`mcp-spring-webflux`, `mcp-spring-webmvc`) or manual setup for web frameworks.

### Comparison: Building Servers

| Feature                  | C# (.NET DI Extensions)                | Java (Builder Pattern)                           | Notes                                                                                                                                                             |
| :----------------------- | :------------------------------------- | :----------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Configuration Style**  | Fluent Extensions on `IServiceCollection` | Fluent Methods on `Sync/AsyncSpecification`    | C# ties into the standard DI configuration flow. Java uses a self-contained builder.                                                                            |
| **Handler Registration** | Attribute Discovery / DI / Manual Handlers | Passing `*Specification` objects to builder | C# offers more automatic discovery via attributes. Java requires explicitly creating specification objects containing both metadata and the handler lambda/method reference. |
| **Transport Config**     | Builder Extensions (`.With*Transport`)   | Passed to initial Builder method               | Transport choice is made earlier in Java's builder flow. C# configures it via extensions.                                                                       |
| **Capabilities**         | Often inferred or set via Options      | Set via `.capabilities()` method               | Both allow explicit capability setting, but C# DI extensions might infer some based on registered handlers/tools.                                                   |
| **Dependencies**         | Standard .NET DI                       | Handlers receive `Exchange` object             | C# leverages DI for injecting services into tools/prompts. Java provides context via the `Exchange` object passed to handlers.                                      |
| **Framework Fit**        | Idiomatic for ASP.NET Core/Generic Host | Standard Java Builder; specific Spring modules | C# feels very native to modern .NET development. Java provides good core flexibility and dedicated Spring modules for framework integration.                      |

### End-User Impact: Stability, Features, and Integration

The way server APIs are designed impacts the end user indirectly but significantly:

1.  **Developer Productivity:** Easier configuration (subjective, but arguably Python > C# > Java core in terms of boilerplate for simple cases) means developers can ship MCP features faster.
2.  **Robustness:** Clear configuration patterns reduce the chance of misconfiguration. C#'s DI helps manage dependencies for complex tools, while Java's explicit specifications ensure handlers are correctly associated.
3.  **Integration Depth:** Framework-specific integrations (ASP.NET Core, Spring) allow MCP servers to leverage existing authentication, logging, monitoring, and deployment infrastructure within enterprise applications, leading to more polished and maintainable features for users.
4.  **Feature Availability:** The ease (or difficulty) of implementing specific MCP capabilities (like dynamic updates, complex resources) in the SDK influences whether developers will expose those advanced features to end-users.

### Conclusion

Both the C# and Java MCP SDKs provide capable high-level APIs for building servers, but they reflect the distinct idioms of their ecosystems. C# embraces the .NET dependency injection and hosting model, offering fluent configuration through extension methods and convenient attribute-based discovery. Java utilizes a classic Builder pattern, separating sync/async concerns early and requiring explicit handler "Specification" objects, while providing dedicated modules for seamless Spring integration.

Neither approach is inherently superior; the best fit depends on the target platform and developer preference. C#'s DI integration might appeal strongly to ASP.NET Core developers, while Java's explicit Builder and dedicated Spring modules cater well to the JVM world. Both successfully abstract much of the underlying protocol complexity, enabling developers to focus on building valuable MCP integrations.

Having explored the high-level server APIs, our next post will delve into the **low-level server internals**, examining the core `Server` and session management classes to understand the foundational mechanics shared by both high-level approaches.

---
