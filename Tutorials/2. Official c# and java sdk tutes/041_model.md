Okay, here's a detailed draft for Blog Post 5, focusing on the client-side APIs in the C# and Java MCP SDKs.

---

## Blog 5: Client APIs - Consuming MCP Services in .NET and Java

**Series:** Deep Dive into the Model Context Protocol SDKs (C# & Java)
**Post:** 5 of 10

In our series exploring the Model Context Protocol (MCP) SDKs, we've spent the last few posts dissecting the server-side architecture – from the [high-level APIs](link-to-post-3) to the [low-level internals](link-to-post-4). Now, we pivot to the other essential half of the equation: the **MCP Client**.

Clients are the applications that *consume* the context (Resources) and capabilities (Tools, Prompts) exposed by MCP servers. They might be AI chatbots needing to call external tools, IDE extensions providing code context, or any application aiming to leverage services offered through the standardized MCP interface.

This post focuses on the primary interfaces and classes provided by the C# and Java SDKs for building these clients:

*   **C# SDK:** The `IMcpClient` interface and its creation via `McpClientFactory`.
*   **Java SDK:** The `McpAsyncClient` and `McpSyncClient` classes, configured via the `McpClient.async/sync` builders.

We'll examine how developers use these APIs to connect to servers, perform the initialization handshake, make requests (like listing/calling tools, reading resources, getting prompts), and handle server-sent notifications.

### The Client Interfaces: Your Window to the MCP World

Both SDKs provide well-defined entry points for client-side operations:

1.  **C# (`IMcpClient` - `src/ModelContextProtocol/Client/IMcpClient.cs`):**
    *   An interface defining the contract for an MCP client.
    *   Inherits from `IMcpEndpoint` (shared methods like `SendMessageAsync`, `SendRequestAsync`, `RegisterNotificationHandler`, `DisposeAsync`).
    *   Adds properties specific to a connected client: `ServerCapabilities`, `ServerInfo`, `ServerInstructions`.
    *   Concrete implementation (`McpClient`) is typically obtained via `McpClientFactory.CreateAsync`.
    *   Interaction is primarily through **extension methods** defined in `McpClientExtensions` (e.g., `client.ListToolsAsync()`, `client.CallToolAsync(...)`).

2.  **Java (`McpAsyncClient` / `McpSyncClient` - `mcp/src/.../client/`):**
    *   Two distinct concrete classes offering either asynchronous (Project Reactor `Mono`/`Flux`) or synchronous (blocking) APIs.
    *   Created using the `McpClient.async(...)` or `McpClient.sync(...)` static builder methods.
    *   Both classes provide direct methods for MCP operations (e.g., `client.listTools()`, `client.callTool(...)`, `client.readResource(...)`).
    *   They internally manage an `McpClientSession` which handles the core protocol logic over a chosen transport.

### Connecting and Initializing: The Handshake Revisited

As we saw from the server perspective, establishing an MCP connection requires an initialization handshake. The client SDKs manage this process.

**C# (`McpClientFactory.CreateAsync`):**

The factory pattern in C# encapsulates both transport connection *and* the MCP initialize handshake.

```csharp
using ModelContextProtocol.Client;
using ModelContextProtocol.Protocol.Transport;
using Microsoft.Extensions.Logging; // Optional

// 1. Create Transport (e.g., Stdio)
var transport = new StdioClientTransport(new StdioClientTransportOptions {
    Command = "path/to/server/executable",
    // ... other options
});

// 2. Define Client Options (Optional)
var clientOptions = new McpClientOptions {
    ClientInfo = new() { Name = "MyDotNetClient", Version = "1.0" },
    Capabilities = new() { Sampling = new() { /* ... handler ... */ } }
    // InitializationTimeout = TimeSpan.FromSeconds(45)
};

// 3. Create and Connect using the Factory
// This single call:
//   - Calls transport.ConnectAsync() to get an ITransport session
//   - Creates the internal McpClient/McpSession
//   - Sends the 'initialize' request
//   - Processes the 'initialize' response
//   - Sends the 'notifications/initialized' notification
//   - Returns the ready-to-use IMcpClient
IMcpClient client = await McpClientFactory.CreateAsync(
    transport,
    clientOptions,
    loggerFactory // Optional
    // CancellationToken can be passed here
);

Console.WriteLine($"Connected to: {client.ServerInfo.Name} v{client.ServerInfo.Version}");
// Client is now ready to use
```

**Java (`McpClient.async/sync(...).build()` then `client.initialize()`):**

Java uses the builder pattern, and initialization is an explicit *first step* after building the client instance.

```java
import io.modelcontextprotocol.client.*;
import io.modelcontextprotocol.client.transport.*;
import io.modelcontextprotocol.spec.*;
import io.modelcontextprotocol.spec.McpSchema.*;
import reactor.core.publisher.Mono; // If using async

// 1. Create Transport (e.g., Stdio)
McpClientTransport transport = new StdioClientTransport(
    ServerParameters.builder("path/to/server/executable").build()
);

// 2. Configure and Build Client (Async example)
McpAsyncClient asyncClient = McpClient.async(transport)
    .requestTimeout(Duration.ofSeconds(10))
    .clientInfo(new Implementation("MyJavaClient", "1.0"))
    .capabilities(ClientCapabilities.builder().sampling().build())
    // .sampling(...) - Register sampling handler if needed
    .build();

// 3. Explicitly Initialize (Performs the handshake)
try {
    // initialize() returns the InitializeResult (or throws McpError)
    InitializeResult initResult = asyncClient.initialize().block(); // block() for sync example
    System.out.println("Connected to: " + initResult.serverInfo().name());
    // Client is ready
} catch (McpError e) {
    System.err.println("Initialization failed: " + e.getMessage());
    asyncClient.close(); // Important to close if init fails
    return;
} catch (Exception e) {
    System.err.println("Connection failed: " + e.getMessage());
    asyncClient.close();
    return;
}

// ... use client ...

asyncClient.closeGracefully().block(); // Close when done
```

**Comparison:** C#'s factory method provides a slightly more convenient "connect and initialize" single step. Java's explicit `initialize()` call makes the handshake boundary clearer in the code flow. Both achieve the same outcome: a connected and initialized client ready for MCP operations.

### Interacting with Server Primitives

Once initialized, clients interact with the server's Tools, Resources, and Prompts using intuitive methods.

**Listing Primitives:**

```csharp
// C# (using extension methods on IMcpClient)
IList<McpClientTool> tools = await client.ListToolsAsync();
IList<McpClientPrompt> prompts = await client.ListPromptsAsync();
IList<Resource> resources = await client.ListResourcesAsync();
IList<ResourceTemplate> templates = await client.ListResourceTemplatesAsync();
```

```java
// Java (using methods on McpAsyncClient/McpSyncClient)
// Async example
ListToolsResult toolsResult = asyncClient.listTools().block(); // or subscribe()
ListPromptsResult promptsResult = asyncClient.listPrompts().block();
ListResourcesResult resourcesResult = asyncClient.listResources().block();
ListResourceTemplatesResult templatesResult = asyncClient.listResourceTemplates().block();

// Sync example
// ListToolsResult toolsResult = syncClient.listTools();
// ... etc ...
```

**Calling a Tool:**

```csharp
// C# (using extension method)
CallToolResponse response = await client.CallToolAsync(
    "calculate_sum",
    new Dictionary<string, object?> { ["a"] = 5, ["b"] = 10 }
);
// Access response.Content, response.IsError

// Or using the McpClientTool wrapper (integrates with Microsoft.Extensions.AI)
McpClientTool sumTool = tools.First(t => t.Name == "calculate_sum");
JsonElement rawResult = (JsonElement)(await sumTool.InvokeAsync(
    new() { ["a"] = 5, ["b"] = 10 }
));
CallToolResponse typedResponse = JsonSerializer.Deserialize<CallToolResponse>(rawResult /* ... */);
```

```java
// Java (using direct method)
// Async example
CallToolRequest request = new CallToolRequest(
    "calculate_sum",
    Map.of("a", 5, "b", 10)
);
CallToolResult result = asyncClient.callTool(request).block(); // or subscribe()
// Access result.content(), result.isError()

// Sync example
// CallToolResult result = syncClient.callTool(request);
```

**Reading a Resource:**

```csharp
// C# (using extension method)
ReadResourceResult result = await client.ReadResourceAsync("config://app/settings.json");
// Access result.Contents
```

```java
// Java (using direct method)
ReadResourceRequest request = new ReadResourceRequest("config://app/settings.json");
ReadResourceResult result = asyncClient.readResource(request).block(); // or subscribe()
// Access result.contents()
```

**Getting a Prompt:**

```csharp
// C# (using extension method)
GetPromptResult result = await client.GetPromptAsync(
    "summarize_topic",
    new Dictionary<string, object?> { ["topic"] = "MCP Transports" }
);
// Access result.Messages, result.Description
```

```java
// Java (using direct method)
GetPromptRequest request = new GetPromptRequest(
    "summarize_topic",
    Map.of("topic", "MCP Transports")
);
GetPromptResult result = asyncClient.getPrompt(request).block(); // or subscribe()
// Access result.messages(), result.description()
```

**Comparison:** C# relies heavily on extension methods for a fluent API directly on `IMcpClient`. Java provides direct methods on the `McpAsync/SyncClient` classes, requiring manual construction of request objects (`CallToolRequest`, `ReadResourceRequest`, etc.). C#'s `McpClientTool` provides useful integration with `Microsoft.Extensions.AI`'s function calling.

### Handling Server Notifications

Servers can send unsolicited notifications (logging, list changes, resource updates). Clients need to register handlers.

**C# (`RegisterNotificationHandler`):**

Uses an `IAsyncDisposable` pattern. You register a handler for a specific method name and dispose of the registration when done.

```csharp
// C#
using ModelContextProtocol.Protocol.Messages;
using ModelContextProtocol.Protocol.Types;
using System.Text.Json;

// Assuming 'client' is an initialized IMcpClient

// Register handler for logging messages
await using var loggingRegistration = client.RegisterNotificationHandler(
    NotificationMethods.LoggingMessageNotification, // Method constant
    async (notification, cancellationToken) => { // Async lambda handler
        var logParams = JsonSerializer.Deserialize<LoggingMessageNotificationParams>(
            notification.Params, /* options */);
        if (logParams != null) {
            Console.WriteLine($"[SERVER LOG {logParams.Level}]: {logParams.Data}");
        }
    }
);

// Register handler for tool list changes
await using var toolsChangedRegistration = client.RegisterNotificationHandler(
    NotificationMethods.ToolListChangedNotification,
    async (notification, cancellationToken) => {
        Console.WriteLine("Server tool list changed! Refreshing...");
        // Trigger refresh logic, e.g., call client.ListToolsAsync() again
    }
);

// Handlers remain active until 'loggingRegistration' or 'toolsChangedRegistration'
// are disposed (e.g., at the end of an 'await using' block or manually).
```

**Java (Builder Configuration):**

Handlers (Consumers or Functions returning `Mono<Void>`) are passed to the `McpClient.async/sync` builder during setup.

```java
// Java
import io.modelcontextprotocol.client.*;
import io.modelcontextprotocol.spec.McpSchema.*;
import reactor.core.publisher.Mono;
import java.util.List;
import java.util.function.Consumer;
import java.util.function.Function;

// Define consumers/functions
Consumer<List<Tool>> toolsChangedConsumer = tools -> {
    System.out.println("Tools changed (Sync): " + tools.size());
    // Refresh logic
};

Function<LoggingMessageNotification, Mono<Void>> loggingConsumerAsync = notification -> {
    return Mono.fromRunnable(() ->
        System.out.println("[SERVER LOG ASYNC " + notification.level() + "]: " + notification.data())
    );
};

// Configure client builder (Async example)
McpAsyncClient asyncClient = McpClient.async(transport)
    // ... other configurations ...
    .loggingConsumer(loggingConsumerAsync) // For async handlers
    .build();

// Configure client builder (Sync example)
McpSyncClient syncClient = McpClient.sync(transport)
    // ... other configurations ...
    .toolsChangeConsumer(toolsChangedConsumer) // For sync handlers
    .build();

// Handlers are active for the lifetime of the client object.
```

**Comparison:** C# uses a dynamic registration model via `RegisterNotificationHandler` returning an `IAsyncDisposable`, allowing handlers to be added/removed during the client's lifetime. Java registers handlers upfront via the builder, tying their lifetime to the client instance.

### Conclusion: Consistent Access Across Platforms

Both the C# and Java MCP SDKs provide robust and idiomatic ways for client applications to interact with MCP servers.

*   **C#** leverages the `IMcpClient` interface, extension methods, and the `McpClientFactory` for a streamlined connection and interaction experience, integrating well with `async/await` and `System.Text.Json`. Its `McpClientTool` offering smooths integration with `Microsoft.Extensions.AI`.
*   **Java** offers distinct `McpSyncClient` and `McpAsyncClient` classes catering to different programming models, configured via a comprehensive builder pattern and utilizing Project Reactor for asynchronous operations.

While the API styles differ, both SDKs successfully abstract the underlying JSON-RPC communication and MCP specifics, allowing developers to focus on consuming Tools, Resources, and Prompts to build powerful, context-aware applications on their preferred enterprise platform.

Next, we revisit the **transports**, focusing specifically on the C# SDK's ASP.NET Core integration and comparing it to Java's Spring/Servlet-based approaches in **Blog 8: Framework Integration**.

---