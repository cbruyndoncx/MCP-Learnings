Okay, here is a detailed draft for Blog Post 4 in the *new* advanced series structure, focusing on the Tool primitive across all four SDKs.

---

## Blog 4: Exposing Actions - The Tool Primitive: Spec vs. Implementation Across MCP SDKs

**Series:** Deep Dive into the Model Context Protocol SDKs (Advanced Topics)
**Post:** 4 of 12

Having established the [protocol's blueprint](link-to-post-1), the [core language](link-to-post-2), and the vital [initialization handshake](link-to-post-3), we now turn to the most dynamic of the Model Context Protocol (MCP) primitives: **Tools**.

Tools are the mechanism by which MCP servers expose *executable actions* to clients and, crucially, to the Language Models (LLMs) interacting through those clients. They transform MCP from a context-sharing protocol into an *action-enabling* one, allowing AI to query databases, call external APIs, manipulate files, control devices, or perform virtually any computational task the server developer exposes.

This post targets advanced users by dissecting the Tool primitive, comparing its definition in the [MCP specification](https://modelcontextprotocol.io/specification/draft/server/tools) with its concrete implementation across the TypeScript, Python, C#, and Java SDKs. We'll examine:

1.  **Tool Definition:** Metadata (`name`, `description`), Input Schema (`inputSchema`), and Annotations (`annotations`).
2.  **Registration Mechanisms:** How developers register tool logic within each SDK (Methods, Decorators, Attributes, Specifications).
3.  **Input Validation:** How argument schemas are defined and enforced.
4.  **Execution Context:** Accessing session state, server capabilities, and DI services within tool handlers.
5.  **Result & Error Handling:** Returning structured content or signaling execution failures.

### The Tool Specification: Blueprint for Action

The MCP specification defines a `Tool` object communicated during the `tools/list` exchange:

```json
// Simplified Spec Definition
{
  "name": "string (unique identifier)",
  "description": "string (natural language for LLM/user)",
  "inputSchema": {
    "type": "object",
    "properties": { /* JSON Schema for arguments */ },
    "required": [ /* list of required property names */ ]
  },
  "annotations": { /* Optional hints: title, readOnlyHint, etc. */ }
}
```

And the interaction flow:

*   **`tools/list`:** Client discovers available Tools and their schemas.
*   **`tools/call`:** Client (often prompted by an LLM) invokes a tool by `name`, providing `arguments` matching the `inputSchema`.
*   **Server Response (`CallToolResult`):** Contains `content` (a list of `TextContent`, `ImageContent`, `AudioContent`, or `EmbeddedResource`) and an `isError` flag.

The core challenge for SDKs is providing an ergonomic way for developers to define the tool's logic and automatically generate/manage the corresponding metadata and schema, while handling the request/response flow.

### SDK Implementations: Defining and Handling Tools

**1. TypeScript (`McpServer.tool()`): Explicit Schemas, Typed Handlers**

*   **Definition:** Uses the `mcpServer.tool()` method. Requires explicit Zod object schema (`inputSchema`) for arguments. Optional `description` and `annotations` are passed as arguments.
*   **Schema:** Defined using Zod (`z.object({...})`). Descriptions added via `.describe()`.
*   **Handler:** An async function receiving a *type-safe* `args` object (inferred from the Zod schema via generics) and the `RequestHandlerExtra` context object.
*   **Validation:** Zod schema validation is performed *automatically* by the `McpServer` before the handler is called. Invalid arguments result in an `InvalidParams` JSON-RPC error response sent by the SDK.
*   **Context:** Accessed via the `RequestHandlerExtra` parameter (`signal`, `sessionId`, `requestId`, `authInfo`, `sendNotification`, etc.).
*   **Result/Error:** Handler must return `Promise<CallToolResult>`. Exceptions are caught by `McpServer` and converted to `CallToolResult { isError: true }`.

```typescript
// TypeScript Tool Definition
const argsSchema = z.object({ query: z.string().describe("Search query") });
mcpServer.tool<typeof argsSchema>(
  "web_search",
  "Performs a web search",
  argsSchema, // Explicit Zod schema
  { readOnlyHint: true }, // Annotations
  async (args, extra): Promise<CallToolResult> => {
    extra.signal.throwIfAborted(); // Check cancellation
    const results = await performWebSearch(args.query);
    await extra.sendNotification({ /* ... logging ... */});
    return { content: [{ type: "text", text: JSON.stringify(results) }] };
  }
);
```

**2. Python (`@mcp.tool()`): Decorators, Type Hint Inference**

*   **Definition:** Uses the `@mcp.tool()` decorator on a standard Python function (sync or async). `name` defaults to function name, `description` to docstring.
*   **Schema:** *Inferred automatically* from function parameter type hints using Pydantic internally (`func_metadata`). Pydantic `Field` or `Annotated` provide descriptions/defaults.
*   **Handler:** The decorated function itself. Receives validated arguments directly.
*   **Validation:** Performed *automatically* by the underlying tool runner logic (`Tool.run` via `fn_metadata.call_fn_with_arg_validation`). Handles basic type coercion and JSON string parsing. Validation errors result in a `ToolError` caught by `FastMCP`, returning `CallToolResult { isError: true }`.
*   **Context:** Optional injection via `ctx: Context` type hint. Provides high-level helpers (`.info`, `.report_progress`).
*   **Result/Error:** Handler can return various types (str, list, dict, model, `Image`, `Content`), automatically converted by `FastMCP` to `CallToolResult.content`. Exceptions are caught and converted to `isError: true` results.

```python
# Python Tool Definition
from mcp.server.fastmcp import FastMCP, Context
from pydantic import Field
from typing import Annotated

mcp = FastMCP("PyServer")

@mcp.tool()
async def web_search_py(
    query: Annotated[str, Field(description="Search query")],
    ctx: Context
) -> list[dict]: # Return type helps schema but primarily for documentation here
    """Performs a web search (docstring description)."""
    ctx.info(f"Searching for: {query}")
    # ctx.signal not directly exposed, cancellation handled internally?
    results = await performWebSearch(query) # Assume async search function
    return results # Returns list of dicts, converted to text content JSON
```

**3. C# (`[McpServerTool]`): Attributes, DI, `AIFunction`**

*   **Definition:** Uses `[McpServerTool]` attribute on static or instance methods within a class marked `[McpServerToolType]`. `Name`, `Description`, and `ToolAnnotations` (`ReadOnly`, `Destructive`, etc.) are properties on the attribute.
*   **Schema:** Generated *internally* by `AIFunctionFactory` based on method parameter reflection (excluding context/DI params). Parameter descriptions use `[Description]` attribute.
*   **Handler:** The attributed method itself.
*   **Validation:** Performed *automatically* by the `AIFunction` invocation mechanism using the generated schema. Validation failures likely surface as exceptions caught by the `AIFunctionMcpServerTool` wrapper.
*   **Context:** Injected as method parameters: `IMcpServer`, `RequestContext<CallToolRequestParams>`, `CancellationToken`, `IProgress<>`, `IServiceProvider`, plus other services via DI.
*   **Result/Error:** Handler can return various types (`string`, `Content`, `AIContent`, `IEnumerable<>` thereof, `CallToolResponse`), automatically converted by `AIFunctionMcpServerTool` wrapper. Exceptions are caught and converted to `isError: true` results.

```csharp
// C# Tool Definition
using ModelContextProtocol.Server;
using System.ComponentModel;
using Microsoft.Extensions.AI; // For AIContent

[McpServerToolType]
public class SearchTools(HttpClient httpClient) // Constructor DI
{
    [McpServerTool(Name = "web_search_cs", ReadOnly = true)]
    [Description("Performs a web search (attribute description)")]
    public async Task<List<AIContent>> WebSearch( // Can return AIContent directly
        RequestContext<CallToolRequestParams> context,
        [Description("Search query")] string query,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested(); // Manual cancellation check
        var results = await performWebSearch(httpClient, query); // Uses injected HttpClient
        await context.Server.SendNotificationAsync(/* ... logging ... */);
        return results.Select(r => new TextContent(r)).ToList<AIContent>();
    }
}
```

**4. Java (`Async/SyncToolSpecification`): Explicit Specs, Exchange Object**

*   **Definition:** Requires creating a `Tool` record (with `name`, `description`, `inputSchema` as a JSON string or Map) and pairing it with a handler `BiFunction` within an `Async/SyncToolSpecification`. These specs are passed to the `McpServer` builder.
*   **Schema:** Developer must provide the JSON Schema definition manually when creating the `Tool` record.
*   **Handler:** A `BiFunction` taking `McpAsync/SyncServerExchange` and `Map<String, Object>` (raw arguments).
*   **Validation:** *Not* automatically performed by the core SDK before calling the handler. The handler receives the raw `Map` and is responsible for validating it against the schema provided in the `Tool` metadata (likely using Jackson's schema validation features if desired).
*   **Context:** Accessed via the `McpAsync/SyncServerExchange` object (first parameter to the handler), providing methods like `.loggingNotification()`, `.getClientCapabilities()`, etc. Access to the underlying `McpServerSession` allows sending arbitrary notifications/requests.
*   **Result/Error:** Handler must explicitly return a `CallToolResult` (Sync) or `Mono<CallToolResult>` (Async). It must manually catch its own exceptions and construct an `isError: true` result if needed. Uncaught exceptions may terminate the session processing.

```java
// Java Tool Definition
BiFunction<McpAsyncServerExchange, Map<String, Object>, Mono<CallToolResult>> searchHandler =
    (exchange, args) -> Mono.defer(() -> {
        // Manual validation recommended here using args and toolMeta.inputSchema()
        String query = (String) args.get("query");
        if (query == null) {
            return Mono.just(new CallToolResult(List.of(new TextContent("Missing query")), true));
        }
        // Access context: exchange.loggingNotification(...); exchange.getSessionId();
        // Check cancellation: exchange.getCancellationToken().isCancellationRequested()
        return performWebSearchAsync(query) // Assume returns Mono<List<String>>
            .map(results -> new CallToolResult(
                results.stream().map(r -> (Content) new TextContent(r)).collect(Collectors.toList()),
                false // Explicitly set isError
            ))
            .onErrorResume(e -> Mono.just(
                new CallToolResult(List.of(new TextContent(e.getMessage())), true) // Manual error result
            ));
    });

String schemaJson = "{\"type\":\"object\", \"properties\": {\"query\": {\"type\":\"string\"}}, \"required\":[\"query\"]}";
Tool searchToolMeta = new Tool("web_search_java", "Performs web search", schemaJson);
AsyncToolSpecification searchSpec = new AsyncToolSpecification(searchToolMeta, searchHandler);

// Register with builder
McpServer.async(provider).tools(searchSpec).build();
```

### Advanced Considerations Synthesized

*   **Schema Definition & Validation:** TS/Python/C# offer more integrated approaches where the schema is derived from or linked directly to the code signature, enabling automatic validation *before* the handler runs. Java requires manual schema provision and validation within the handler is the developer's responsibility in the core SDK.
*   **Boilerplate:** Python's decorators are the most concise. Java's Specification objects require the most boilerplate. TS and C# fall in between.
*   **Context Provision:** Python's `Context` injection and C#'s DI parameter injection are arguably the most ergonomic for accessing contextual features or dependencies. Java's `Exchange` object and TS's `RequestHandlerExtra` are functional but slightly less direct.
*   **Result Handling:** Python's automatic conversion of various return types is highly convenient. C# also handles several common types well. TS and Java require more explicit construction of the `CallToolResult` object.
*   **Error Handling:** TS, Python, and C# wrappers provide automatic conversion of uncaught exceptions to `isError: true` results. Java handlers must generally manage their own exceptions and construct the error result manually.
*   **Dynamic Updates:** Only the TS SDK provides a clear high-level API (via `RegisteredTool` handles) for modifying tools post-connection. Others require interacting with lower-level mechanisms or manual notification sending.
*   **Annotations:** TS and C# attributes allow specifying `ToolAnnotations` declaratively alongside the tool definition. Python and Java require manual creation and association if needed (though not shown in Java's core Spec objects).

### Conclusion: Matching Tooling to Task and Team

Exposing application logic as MCP Tools is a powerful way to enhance AI capabilities. Each SDK provides viable mechanisms, but with distinct trade-offs suiting different developer preferences and project needs:

*   **TypeScript:** Best for explicit control, strong typing via Zod, integrated annotations, and dynamic updates. Requires clear schema definition.
*   **Python:** Offers the most rapid development experience with `FastMCP` decorators, type-hint inference, and flexible result conversion. Ideal for wrapping existing Python code.
*   **C#:** Excels in DI integration, leveraging attributes for discovery and configuration, and integrating seamlessly with `Microsoft.Extensions.AI`. Provides robust type safety and performance.
*   **Java:** Provides clear Sync/Async separation and targeted Spring/Servlet integration. Requires more explicit configuration via Specification objects and manual error/result construction in handlers.

Advanced developers choosing an SDK for complex tool implementation should weigh the importance of automatic schema generation/validation, ease of dependency injection, required transport features (resumability), and the desired level of explicitness versus convention in their server definition. Understanding these nuances ensures the selection of the SDK best aligned with the project's technical requirements and the development team's workflow.

---