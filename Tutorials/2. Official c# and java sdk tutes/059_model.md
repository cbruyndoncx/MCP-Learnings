Okay, let's draft Blog Post 11, targeting advanced users and focusing on the definition and execution of MCP Tools across the four SDKs.

---

## Blog 11: Advanced Tooling - Defining & Executing MCP Tools Across SDKs

**Series:** Deep Dive into the Model Context Protocol SDKs
**Post:** 11 of 10 (Advanced Topics)

Having navigated the core architecture, transports, and basic usage patterns of the Model Context Protocol (MCP) SDKs for TypeScript, Python, C#, and Java in our [initial 10-part series](link-to-post-10), we now venture into more advanced territory. This post focuses specifically on the **Tool** primitive – arguably the most powerful mechanism for extending AI capabilities via MCP – targeting developers who need fine-grained control and deeper understanding.

We'll dissect how Tools are defined, how their input schemas are managed, how execution context is provided, and how results and errors are handled across the four SDKs, highlighting the nuances critical for building complex, robust, and maintainable MCP tools.

### The Anatomy of an MCP Tool

At its core, defining an MCP Tool involves two key components, regardless of the SDK:

1.  **Metadata & Schema:** Information *about* the tool, exposed to the client via the `tools/list` request. This includes:
    *   `name`: The unique identifier used in `tools/call`.
    *   `description`: A natural language explanation for the LLM (and potentially the user).
    *   `inputSchema`: A JSON Schema (specifically, `{"type": "object", ...}`) defining the expected arguments, their types, and which are required.
    *   `annotations` (Optional): Hints about the tool's behavior (`readOnlyHint`, `destructiveHint`, etc.).
2.  **Handler Logic:** The actual code (a function, method, or delegate) that executes when the tool is invoked via a `tools/call` request. This logic receives the validated arguments and performs the desired action.

The SDKs differ significantly in *how* these two components are defined, linked, and executed.

### TypeScript: Explicit Schemas and Handler Functions

The TypeScript `McpServer` uses explicit method calls and relies heavily on Zod for schema definition.

*   **Definition (`McpServer.tool()`):**
    *   Overloads accept `name`, optional `description`, an explicit `z.ZodObject` for the `inputSchema`, optional `annotations`, and the handler `callback`.
    *   Zod schemas define argument types, descriptions (`.describe()`), and optionality (`.optional()`).
    *   The returned `RegisteredTool` handle allows post-connection updates (`.update()`, `.enable()`, etc.).

    ```typescript
    import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
    import { z } from "zod";
    import { RequestHandlerExtra } from "@modelcontextprotocol/sdk/shared/protocol.js";
    import { CallToolResult, ServerRequest, ServerNotification } from "@modelcontextprotocol/sdk/types.js";

    const mcpServer = new McpServer(/* ... */);

    const complexArgsSchema = z.object({
        userId: z.string().uuid().describe("Target user ID"),
        retries: z.number().int().positive().optional().default(3),
        metadata: z.record(z.any()).optional().describe("Optional metadata")
    });

    mcpServer.tool<typeof complexArgsSchema>( // Generic ensures type safety
      "complex_op",
      "Performs a complex operation",
      complexArgsSchema, // Explicit Zod schema
      { readOnlyHint: false, destructiveHint: true }, // Annotations
      // Handler receives validated args and 'extra' context
      async (args: z.infer<typeof complexArgsSchema>, extra: RequestHandlerExtra<ServerRequest, ServerNotification>): Promise<CallToolResult> => {
          console.log(`Executing complex_op for user ${args.userId} on session ${extra.sessionId}`);
          // Access auth info: extra.authInfo
          // Access cancellation: extra.signal
          // Send progress: await extra.sendNotification(...)
          try {
              // Use args.retries, args.metadata
              // ... perform operation ...
              return { content: [{ type: "text", text: "Success" }] };
          } catch (e) {
              return {
                  content: [{ type: "text", text: `Failed: ${e.message}` }],
                  isError: true
              };
          }
      }
    );
    ```
*   **Execution Flow:** `tools/call` arrives -> `McpServer` finds registered tool -> Zod schema validates `arguments` -> Handler `callback` is invoked with validated `args` and `RequestHandlerExtra`.
*   **Context:** Provided explicitly via the `RequestHandlerExtra` parameter, containing `signal`, `sessionId`, `requestId`, `authInfo`, `_meta`, `sendNotification`, and `sendRequest`.
*   **Result Handling:** Handler must return a `CallToolResult` object (or a Promise thereof). Errors thrown within the handler are caught by `McpServer` and automatically converted into an `isError: true` `CallToolResult`.

### Python: Decorators, Type Hints, and Context Injection

Python's `FastMCP` prioritizes ergonomics using decorators and type hint inference.

*   **Definition (`@mcp.tool()`):**
    *   The decorator registers the function. `name` defaults to function name, `description` to docstring.
    *   Argument types and defaults are inferred from Python type hints. Pydantic `Field` or `Annotated` can add descriptions/constraints.
    *   The `inputSchema` is generated *internally* using Pydantic introspection (`func_metadata`).
    *   Annotations are *not* directly supported via the decorator in the current examples/core API.

    ```python
    from mcp.server.fastmcp import FastMCP, Context
    from pydantic import Field, BaseModel
    from typing import Annotated

    mcp = FastMCP("PyServer")

    class Metadata(BaseModel):
        source: str
        timestamp: float | None = None

    @mcp.tool()
    async def complex_op_py(
        user_id: Annotated[str, Field(description="Target user ID")], # Use Field for description
        retries: int = 3, # Default value
        metadata: Metadata | None = None, # Optional complex type
        ctx: Context | None = None # Optional context injection
    ) -> list[str]: # Return type hints for schema/validation are less critical here
        """Performs a complex operation (docstring is description)."""
        if ctx:
            ctx.info(f"Executing complex_op_py for {user_id} (Req ID: {ctx.request_id})")
            # Use ctx.report_progress, ctx.read_resource, etc.
        # ... use validated user_id, retries, metadata ...
        results = [f"Processed {user_id}", f"Retries: {retries}"]
        if metadata:
            results.append(f"Source: {metadata.source}")
        return results # Can return various types, auto-converted
    ```
*   **Execution Flow:** `tools/call` arrives -> `FastMCP` finds tool -> Internal Pydantic model validates `arguments` (including attempting JSON parsing for strings) -> Handler function is called with validated args -> If `Context` is requested, it's injected.
*   **Context:** Injected via type hint (`ctx: Context`). Provides convenient methods (`.info`, `.error`, `.report_progress`, `.read_resource`) and properties (`.request_id`, `.session`, `.request_context`).
*   **Result Handling:** Handler can return various types (primitives, lists, dicts, Pydantic models, `Image`, `TextContent`, `ImageContent`, etc.). `FastMCP` automatically converts the return value into the list of `Content` objects required by `CallToolResult`. Exceptions are caught and returned as `isError: true` results.

### C#: Attributes, Dependency Injection, and AIFunction

The C# SDK relies heavily on attributes for discovery and .NET DI for wiring dependencies and context.

*   **Definition (`[McpServerTool]`, `[McpServerToolType]`):**
    *   Methods marked `[McpServerTool]` within classes marked `[McpServerToolType]` are registered (often via `.WithToolsFromAssembly()`).
    *   `Name` and `Description` can be set on the attribute or inferred from the method/`[Description]` attribute. Tool Annotations (`ReadOnly`, `Destructive`, etc.) are properties on the `[McpServerTool]` attribute.
    *   The `inputSchema` is generated internally using `AIFunctionFactory` based on method parameters (excluding DI/MCP context parameters). Parameter descriptions come from `[Description]` attributes.
    *   `McpServerTool.Create(...)` methods allow programmatic registration.

    ```csharp
    using ModelContextProtocol.Server;
    using System.ComponentModel;
    using Microsoft.Extensions.Logging;
    using Microsoft.Extensions.DependencyInjection; // For FromKeyedServices
    using ModelContextProtocol.Protocol.Types; // For Content

    [McpServerToolType]
    public class ComplexToolOps(ILogger<ComplexToolOps> logger, SomeScopedService scopedService) // Constructor DI
    {
        // Annotations set on the attribute
        [McpServerTool(Name = "complex_op_cs", ReadOnly = false, Destructive = true)]
        [Description("Performs a complex operation (attribute description)")]
        public async Task<IEnumerable<Content>> ExecuteComplexOp(
            IMcpServer server, // MCP Server context injected
            RequestContext<CallToolRequestParams> context, // Full request context
            [Description("Target user ID")] Guid userId, // Parameter description
            int retries = 3, // Default value
            [FromKeyedServices("my_http")] HttpClient specificHttpClient) // Keyed DI
        {
            logger.LogInformation("Executing complex_op_cs for {UserId} on session {SessionId}",
                userId, context.Server.GetHashCode()); // Example: Using logger and context

            // Use injected dependencies: scopedService, specificHttpClient
            // Send progress: await server.NotifyProgressAsync(...) using context.Params?.Meta?.ProgressToken
            // Check cancellation: context.RequestAborted

            try {
                // ... perform operation ...
                return [new Content { Type = "text", Text = "Success" }];
            } catch (Exception e) {
                return [new Content { Type = "text", Text = $"Failed: {e.Message}" }];
                // Note: To signal error back via MCP, the *handler* itself would need
                // to return CallToolResponse with IsError=true, or throw McpException.
                // Simply returning error text here doesn't set IsError.
                // Or, modify the internal AIFunctionMcpServerTool's InvokeAsync.
            }
        }
    }
    ```
*   **Execution Flow:** `tools/call` arrives -> ASP.NET Core routes to MCP handler -> `McpServer`/`McpSession` finds registered `McpServerTool` -> `AIFunctionMcpServerTool.InvokeAsync` is called -> It uses `AIFunctionFactory` logic which:
    *   Parses/Validates arguments from the request against the generated schema.
    *   Resolves DI parameters (scoped or singleton based on tool class registration).
    *   Injects MCP context parameters (`IMcpServer`, `RequestContext`, `CancellationToken`, `IProgress<>`).
    *   Invokes the target method.
*   **Context:** Can be injected as method parameters: `IMcpServer`, `RequestContext<CallToolRequestParams>`, `CancellationToken`, `IProgress<ProgressNotificationValue>`, `IServiceProvider`.
*   **Result Handling:** The handler method's return value is processed by `AIFunctionMcpServerTool.InvokeAsync`. It handles standard types (`string`, `Content`, `AIContent`, `IEnumerable<>` of these, `CallToolResponse`) and serializes others to JSON text. *Crucially, by default, exceptions thrown by the tool method result in an `isError: true` `CallToolResponse` containing the error message, handled within `AIFunctionMcpServerTool`.*

### Java: Explicit Specifications and Exchange Objects

Java uses an explicit builder pattern where `ToolSpecification` objects (pairing metadata and handlers) are registered.

*   **Definition (`McpServerFeatures.Async/SyncToolSpecification`):**
    *   You create a `Tool` record/object containing `name`, `description`, and `inputSchema` (as a `String` containing JSON Schema, parsed internally).
    *   You create a `BiFunction` handler taking `McpAsync/SyncServerExchange` and `Map<String, Object>` (arguments) and returning `Mono<CallToolResult>` (Async) or `CallToolResult` (Sync).
    *   These are bundled into an `Async/SyncToolSpecification` and passed to the `McpServer.async/sync(...).tools(...)` builder method.

    ```java
    import io.modelcontextprotocol.server.*;
    import io.modelcontextprotocol.spec.McpSchema.*;
    import io.modelcontextprotocol.spec.McpSchema.Tool; // Alias if needed
    import reactor.core.publisher.Mono;
    import java.util.List;
    import java.util.Map;

    // Assume 'objectMapper' is available
    String complexSchema = objectMapper.writeValueAsString(Map.of(
        "type", "object",
        "properties", Map.of(
            "userId", Map.of("type", "string", "format", "uuid"),
            "retries", Map.of("type", "integer", "default", 3),
            "metadata", Map.of("type", "object") // Simplified
        ),
        "required", List.of("userId")
    ));

    Tool complexToolMeta = new Tool("complex_op_java", "Performs complex op", complexSchema);

    // Async Handler Function (BiFunction)
    BiFunction<McpAsyncServerExchange, Map<String, Object>, Mono<CallToolResult>> asyncHandler =
        (exchange, args) -> {
            String userId = (String) args.get("userId");
            // Access client info: exchange.getClientInfo()
            // Send notifications: exchange.loggingNotification(...)
            // Request sampling: exchange.createMessage(...)
            System.out.println("Async executing for " + userId);
            // ... async logic ...
            return Mono.just(new CallToolResult(List.of(new TextContent("Async Success")), false));
            // On error: return Mono.just(new CallToolResult(List.of(new TextContent(e.getMessage())), true));
        };

    AsyncToolSpecification asyncSpec = new AsyncToolSpecification(complexToolMeta, asyncHandler);

    // Register with builder
    McpAsyncServer server = McpServer.async(transportProvider)
        // ... other config ...
        .tools(asyncSpec)
        .build();
    ```
*   **Execution Flow:** `tools/call` arrives -> Transport Provider routes to `McpServerSession` -> Session finds handler in `requestHandlers` map -> Invokes the registered `BiFunction`, passing an `McpAsync/SyncServerExchange` and the raw argument `Map<String, Object>`. Argument validation against the `inputSchema` is *not* automatically performed by the core session before calling the handler (though it *could* be done within a custom handler or potentially by a higher-level framework).
*   **Context:** Provided via the `McpAsync/SyncServerExchange` object passed as the *first* argument to the handler `BiFunction`. Contains methods like `.createMessage()`, `.listRoots()`, `.getClientCapabilities()`, `.loggingNotification()`.
*   **Result Handling:** The handler *must* return a `CallToolResult` (Sync) or `Mono<CallToolResult>` (Async). Error handling (setting `isError: true`) must be done *within* the handler logic. Uncaught exceptions might terminate the session handling loop if not caught appropriately before returning from the handler `BiFunction`.

### Synthesis & Advanced Considerations

*   **Schema Definition:** TS (Zod) and C# (Attributes/Reflection/SourceGen) offer more integrated schema generation from code signatures compared to Java's need for manually providing the JSON Schema string (or Map) when creating the `Tool` metadata object. Python's inference is the most automatic.
*   **Argument Validation:** TS (Zod), Python (Pydantic internal), and C# (AIFunctionFactory internal) perform automatic argument validation against the derived/provided schema before calling the handler. Java's core SDK requires manual validation within the handler based on the provided schema, although framework integrations might add layers.
*   **Context Access:** Python (`Context`) and C# (`RequestContext`/DI Params) provide the most ergonomic access within high-level APIs. Java's `Exchange` object is explicit but functional. TS requires using the `RequestHandlerExtra` object.
*   **Result Conversion:** Python's `FastMCP` offers the most automatic conversion from various return types to `CallToolResult.Content`. C# handles several common types automatically. Java and TS generally require the handler to explicitly construct the `CallToolResult`.
*   **Error Handling:** C# and TS have more centralized error catching that converts exceptions to `isError: true` results. Java handlers need to manage this more explicitly to avoid potentially crashing the session loop. Always prefer returning `CallToolResult(..., isError=true)` over throwing exceptions from handlers unless it's an unrecoverable server error.
*   **Dependency Injection:** C# has the most seamless DI integration for tool implementations. Java requires manual wiring, typically in Spring `@Configuration`. TS/Python depend on the patterns of their respective web frameworks or manual passing.
*   **Security:** Remember that `CallToolRequestParams.Arguments` comes from the client and **must be treated as untrusted input**. Sanitize and validate rigorously, especially if arguments are used in database queries, file paths, or system calls. Do not rely solely on the `inputSchema` for security validation.

### Conclusion

Defining and executing MCP Tools involves a blend of protocol metadata and application logic. The SDKs provide different pathways reflecting their language idioms: TypeScript's explicitness with Zod and handles, Python's ergonomic decorators and type inference, C#'s deep DI integration and attributes, and Java's explicit Builder pattern with Specification objects and the choice of Sync/Async APIs.

Advanced developers need to understand these underlying mechanisms to effectively leverage dependency injection (especially C#), manage context (`Context`/`Exchange`/`Extra`), handle results and errors gracefully, and potentially implement custom logic when the high-level APIs aren't sufficient. Mastering tool definition and execution is key to unlocking the full potential of MCP for extending AI capabilities.

In our (truly) final synthesis post, we'll wrap up the entire series, comparing the overall developer experience across all four platforms and contemplating the future evolution of the MCP SDK ecosystem.

---