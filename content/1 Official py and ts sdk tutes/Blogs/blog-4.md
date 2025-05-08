---
title: "Blog 4: Under the Hood - The MCP Server Core (TypeScript & Python)"
draft: false
---
## Blog 4: Under the Hood - The MCP Server Core (TypeScript & Python)

**Series:** Deep Dive into the Model Context Protocol SDKs (TypeScript & Python)
**Post:** 4 of 10

In [Blog 3](blog-3.md), we explored the convenient high-level server APIs, `McpServer` (TypeScript) and `FastMCP` (Python), which significantly simplify building Model Context Protocol (MCP) servers. These APIs are excellent for many use cases, providing easy ways to register Tools, Resources, and Prompts.

However, sometimes you need more granular control, want to implement custom protocol extensions, or simply wish to understand the fundamental mechanics of the SDK. For this, we need to dive beneath the high-level wrappers and explore the foundational server components.

This post peels back the abstraction layer to examine:

*   The core `Server` classes in both SDKs.
*   The underlying `Protocol` (TS) and `BaseSession` (Python) classes that manage the actual MCP communication logic.
*   How these lower-level APIs provide maximum flexibility at the cost of some convenience.

### Why Go Low-Level?

Before diving in, why would you bypass the user-friendly `McpServer` or `FastMCP`?

1.  **Maximum Control:** Directly handle specific MCP request methods or notifications with custom logic beyond the standard primitives.
2.  **Custom Extensions:** Implement experimental or non-standard MCP methods or capabilities.
3.  **Fine-Grained Management:** Control exactly how requests are processed, perhaps integrating with complex application state or external systems in ways not easily accommodated by the high-level wrappers.
4.  **Integration:** Embed MCP handling deeply within an existing application or framework where the high-level API structure might be restrictive.
5.  **Understanding:** Gain a deeper appreciation for how the SDK functions internally.

### TypeScript: The `Server` and `Protocol` Foundation

In the TypeScript SDK, the foundation consists of two key classes:

1.  **`Protocol` (`src/shared/protocol.ts`):** This is the base class responsible for the core MCP logic, independent of whether it's a client or server. It handles:
    *   Connecting to a `Transport`.
    *   Managing JSON-RPC message framing (requests, responses, notifications).
    *   Matching request IDs to responses.
    *   Handling timeouts (with `DEFAULT_REQUEST_TIMEOUT_MSEC`) and cancellation (`notifications/cancelled`).
    *   Processing progress notifications (`notifications/progress`).
    *   Providing `request()` and `notification()` methods for sending messages.
    *   Abstract methods for capability assertions (`assertCapabilityForMethod`, etc.).
2.  **`Server` (`src/server/index.ts`):** This class *extends* `Protocol` and specializes it for server-side operation. It implements the server-specific capability checks and primarily exposes methods for registering handlers.

**Working with the Low-Level `Server`:**

Instead of methods like `.tool()` or `.resource()`, you interact with the low-level `Server` primarily through `setRequestHandler` and `setNotificationHandler`.

```typescript
// TypeScript Low-Level Server Example
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  ListPromptsRequestSchema, // Import specific Zod schema
  ListPromptsResult,
  McpError,
  ErrorCode,
  JSONRPCRequest,
  ServerCapabilities,
  Prompt,
  // ... other necessary types
} from "@modelcontextprotocol/sdk/types.js";
import { RequestHandlerExtra } from "@modelcontextprotocol/sdk/shared/protocol.js";

// 1. Instantiate the low-level Server
const lowLevelServer = new Server(
  { name: "LowLevelServer", version: "1.0" },
  {
    // Declare capabilities explicitly
    capabilities: {
      prompts: { listChanged: false } // We'll handle prompts
    }
  }
);

// 2. Register a request handler using a Zod schema
lowLevelServer.setRequestHandler(
  ListPromptsRequestSchema, // Schema for the request type
  // Async handler function receiving the parsed request and extra context
  async (request: z.infer<typeof ListPromptsRequestSchema>, extra: RequestHandlerExtra<any, any>): Promise<ListPromptsResult> => {
    console.log(`Handling listPrompts request (ID: ${extra.requestId}, Session: ${extra.sessionId})`);

    // Access cancellation signal
    if (extra.signal.aborted) {
      throw new McpError(ErrorCode.InternalError, "Request was cancelled");
    }

    // Example: Implement logic to fetch prompts
    const prompts: Prompt[] = [
      { name: "prompt1", description: "First prompt" }
      // ... fetch or define prompts
    ];

    // Return the result conforming to ListPromptsResult schema
    return { prompts };
  }
);

// (Similarly, use setNotificationHandler for notifications)

// 3. Connect to a transport
const transport = new StdioServerTransport();
await lowLevelServer.connect(transport); // Starts listening and handling

console.log("Low-level server connected via stdio.");
```

**Key Takeaways (TS Low-Level):**

*   You explicitly register handlers for specific MCP methods using their corresponding Zod schemas (`ListPromptsRequestSchema`, `CallToolRequestSchema`, etc.).
*   Handler functions receive the validated request object (matching the schema) and an `RequestHandlerExtra` object containing metadata (`signal`, `sessionId`, `requestId`, `authInfo`) and methods to send related messages (`sendNotification`, `sendRequest`).
*   You are responsible for declaring the server's `capabilities` correctly during instantiation.
*   Error handling involves throwing `McpError` or standard Errors, which the `Protocol` layer translates into JSON-RPC error responses.

### Python: The `Server` and `BaseSession` Core

The Python SDK follows a similar pattern, with `BaseSession` providing the core logic and the low-level `Server` specializing it.

1.  **`BaseSession` (`src/mcp/shared/session.py`):** Analogous to TS `Protocol`. Manages the connection state, message sending/receiving via memory streams provided by transports, request/response ID mapping, timeouts, and cancellation. It defines `send_request` and `send_notification`.
2.  **`Server` (`src/mcp/server/lowlevel/server.py`):** This class *uses* a `ServerSession` internally (created during the `run` method). It provides decorators (`@server.call_tool()`, `@server.list_prompts()`, etc.) to register handlers for specific MCP operations. *Note:* This low-level `Server` uses decorators, unlike the TS low-level `Server` which uses explicit handler registration methods.

**Working with the Low-Level `Server`:**

Even the "low-level" Python `Server` uses decorators, making the registration process quite different from TypeScript's low-level approach.

```python
# Python Low-Level Server Example
import anyio
import mcp.types as types
from mcp.server.lowlevel import Server, NotificationOptions
from mcp.server.models import InitializationOptions
from mcp.server.stdio import stdio_server
from mcp.shared.context import RequestContext # For type hinting context

# 1. Instantiate the low-level Server
lowLevelServer = Server(name="LowLevelPyServer", version="1.0")

# 2. Register handlers using decorators
@lowLevelServer.list_prompts()
async def handle_list_prompts() -> list[types.Prompt]:
    # Access context if needed (available during request handling)
    try:
        ctx: RequestContext[ServerSession, Any] = lowLevelServer.request_context
        print(f"Handling listPrompts request (ID: {ctx.request_id}, Session: {ctx.session})")
    except LookupError:
        print("Context not available outside request") # Should not happen here

    prompts: list[types.Prompt] = [
        types.Prompt(name="prompt1", description="First prompt")
        # ... fetch or define prompts
    ]
    return prompts

# Example Tool Handler
@lowLevelServer.call_tool()
async def handle_call_tool(name: str, arguments: dict | None) -> list[types.TextContent]:
     ctx = lowLevelServer.request_context # Access context
     print(f"Calling tool '{name}' for request {ctx.request_id}")
     if name == "echo":
         return [types.TextContent(type="text", text=f"Echo: {arguments.get('msg', '')}")]
     raise ValueError(f"Unknown tool: {name}")

# (Similarly for @server.read_resource, @server.get_prompt, etc.)

# 3. Run the server with a transport
async def main():
    init_options = lowLevelServer.create_initialization_options(
        notification_options=NotificationOptions(), # Define notification capabilities
        experimental_capabilities={}
    )
    async with stdio_server() as (read_stream, write_stream):
        await lowLevelServer.run(read_stream, write_stream, init_options)

if __name__ == "__main__":
    anyio.run(main)
```

**Key Takeaways (Python Low-Level):**

*   Handler registration still uses decorators, even on the low-level `Server`, making it feel somewhat similar to `FastMCP` but requiring manual handling of result types (e.g., returning `list[types.Tool]` instead of just tool info).
*   Request context (`RequestContext`) is accessed via `server.request_context` *during* the execution of a handler.
*   You manually create `InitializationOptions` including `ServerCapabilities`.
*   The core session logic lives within `ServerSession`, which is managed internally by `Server.run()`.

### Core Logic: `Protocol` (TS) & `BaseSession` (Python)

Beneath the `Server` classes lie the true engines: `Protocol` (TS) and `BaseSession` (Python). These abstract base classes implement the state machine and logic for reliable MCP communication over *any* transport.

**Shared Responsibilities:**

*   **Transport Abstraction:** They take read/write streams (from a `Transport` in TS, or directly from transport functions like `stdio_server` in Python) and handle message framing.
*   **JSON-RPC Compliance:** Parsing incoming messages, validating against expected JSON-RPC structure.
*   **Request/Response Matching:** Generating unique request IDs and correlating incoming responses/errors back to the original outgoing request using the `id` field.
*   **Timeout Management:** Implementing the request `timeout` logic (using `setTimeout` in TS, likely `anyio.fail_after` or equivalent in Python). Handling `resetTimeoutOnProgress` and `maxTotalTimeout`.
*   **Cancellation:** Sending `notifications/cancelled` when a request's `AbortSignal` (TS) or `CancelScope` (Python) is triggered, and handling incoming cancellation notifications to abort in-flight request handlers.
*   **Progress Notifications:** Handling incoming `notifications/progress` and routing them to the correct request's `onprogress` callback (TS). Python's `ServerSession` has `send_progress_notification`, implying progress is handled within the request implementation itself.
*   **Error Handling:** Catching errors during request handling and formatting them into `JSONRPCError` responses. Handling incoming `JSONRPCError` responses and rejecting the corresponding request promise/future.

By encapsulating this core logic, `Protocol`/`BaseSession` allows the `Server` classes (and the transport implementations) to focus on their specific roles.

### Comparison: Low-Level APIs

| Feature                | `Server`/`Protocol` (TypeScript)       | `Server`/`BaseSession` (Python)               | Notes                                                                                                   |
| :--------------------- | :--------------------------------------- | :---------------------------------------------- | :------------------------------------------------------------------------------------------------------ |
| **Handler Registration** | `setRequest/NotificationHandler` (explicit) | Decorators (`@server.call_tool`, etc.)        | TS is more explicit, requires Zod schemas. Python uses decorators, feels closer to `FastMCP`.            |
| **Base Class**         | `Protocol` (shared client/server)        | `BaseSession` (shared client/server)            | Similar role, different naming.                                                                         |
| **Context Access**     | `RequestHandlerExtra` (passed to handler)  | `server.request_context` (accessed in handler) | TS passes context data explicitly. Python uses a context variable pattern typical in async frameworks. |
| **Core Logic**         | `Protocol` class                         | `BaseSession` class                             | Both handle JSON-RPC, timeouts, cancellation, progress (though progress handling seems more explicit in TS). |
| **Capability Config**  | Passed to `Server` constructor           | Passed to `Server.run` via `InitializationOptions` | Configuration point differs slightly.                                                                   |

### Conclusion: Power and Responsibility

The low-level `Server` APIs in both the TypeScript and Python MCP SDKs provide the foundational layer upon which the higher-level abstractions are built. They offer maximum flexibility and control, allowing developers to interact directly with the core MCP message flow and implement custom behaviors.

*   **TypeScript's `Server`** demands explicit handler registration using Zod schemas, offering strong type safety at the cost of more boilerplate compared to its Python counterpart.
*   **Python's low-level `Server`** surprisingly retains a decorator-based approach for handler registration, making it quite ergonomic, while still requiring manual construction of MCP response types.

You'd typically reach for these low-level APIs when the `McpServer` or `FastMCP` abstractions don't meet your specific needs – perhaps for implementing non-standard protocol extensions, integrating deeply with another framework, or when requiring precise control over every aspect of the request lifecycle. They grant power but also demand a deeper understanding of the MCP specification itself.

With the server foundations covered, our next post will shift focus to the other side of the conversation: **Blog 5: Client Architecture - Talking to Servers**. We'll explore how `Client` (TS) and `ClientSession` (Python) initiate requests and handle responses and notifications.

---
