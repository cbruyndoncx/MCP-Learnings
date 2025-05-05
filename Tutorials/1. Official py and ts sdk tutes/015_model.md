Okay, here's a detailed draft for Blog Post 5, focusing on the client-side architecture of the MCP SDKs.

---

## Blog 5: Client Architecture - Consuming MCP Services (TypeScript & Python)

**Series:** Deep Dive into the Model Context Protocol SDKs (TypeScript & Python)
**Post:** 5 of 10

So far in our series, we've focused on the *server* side of the Model Context Protocol (MCP) equation. We've explored [type definitions](link-to-post-2) and examined both the [high-level](link-to-post-3) (`McpServer`/`FastMCP`) and [low-level](link-to-post-4) server APIs in TypeScript and Python.

But MCP is a two-way street. Servers expose capabilities, but it's the **clients** that consume them to provide context-aware experiences. Clients could be AI chatbots, integrated development environments (IDEs), browser extensions, or any application that needs to leverage external context or functionality via MCP.

In this post, we shift our focus to the client-side implementations within the MCP SDKs:

*   **TypeScript:** The `Client` class (`src/client/index.ts`).
*   **Python:** The `ClientSession` class (`src/mcp/client/session.py`).

We'll explore how these classes enable applications to connect to MCP servers, discover available primitives (Tools, Resources, Prompts), make requests, and handle asynchronous notifications.

### The Core Client Classes: Your Gateway to MCP Servers

Both SDKs provide a primary class that acts as the main interface for interacting with an MCP server:

1.  **TypeScript (`Client`):** This class extends the shared `Protocol` base class. It provides methods like `connect`, `listTools`, `callTool`, `readResource`, `getPrompt`, etc., offering a clear, method-driven API.
2.  **Python (`ClientSession`):** This class extends the shared `BaseSession` class. It's designed as an asynchronous context manager (`async with ClientSession(...)`). Interaction typically happens through methods on the session object *after* the context is entered (e.g., `session.call_tool(...)`, `session.read_resource(...)`).

Underneath, both `Client` and `ClientSession` rely on the `Protocol`/`BaseSession` logic (discussed in Blog 4) to handle JSON-RPC framing, request/response matching, timeouts, and cancellation over a chosen transport.

### Establishing the Connection: The Handshake

Before any meaningful interaction can occur, the client must connect to the server and perform the MCP initialization handshake.

**TypeScript (`Client.connect`):**

The `Client` instance is created first, and then its `connect` method is called, passing in an *instance* of a specific transport implementation. The `connect` method handles sending the `initialize` request and processing the server's response.

```typescript
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
// Or StreamableHTTPClientTransport, WebSocketClientTransport, etc.

// 1. Create Client instance
const client = new Client(
  { name: "MyTSClient", version: "0.1.0" },
  {
    // Optional: Declare client capabilities
    capabilities: {
      sampling: {}, // We can handle sampling requests
      roots: { listChanged: true } // We can handle root list changes
    }
  }
);

// 2. Create Transport instance
const transport = new StdioClientTransport({
  command: "python", // Or provide URL for HTTP/WS
  args: ["my_mcp_server.py"]
});

async function run() {
  try {
    // 3. Connect (handles initialize handshake internally)
    await client.connect(transport);
    console.log("Connected!");
    console.log("Server Info:", client.getServerVersion());
    console.log("Server Capabilities:", client.getServerCapabilities());
    console.log("Server Instructions:", client.getInstructions());

    // ... proceed with interactions ...

  } catch (error) {
    console.error("Connection failed:", error);
  } finally {
    await client.close(); // Close connection when done
  }
}
run();
```

**Python (`async with ClientSession(...)`):**

The Python approach uses an asynchronous context manager. You typically call a transport *factory function* (like `stdio_client`, `sse_client`) which itself yields the necessary read/write streams to the `ClientSession` constructor. The `ClientSession`'s `__aenter__` method implicitly calls its `initialize` method.

```python
import anyio
from mcp import ClientSession, StdioServerParameters, types
from mcp.client.stdio import stdio_client
# Or sse_client, websocket_client

# 1. Define server parameters (for stdio) or URL (for HTTP/WS)
server_params = StdioServerParameters(
    command="python",
    args=["my_mcp_server.py"]
)

async def run():
    # 2. Use transport factory in async with block
    async with stdio_client(server_params) as (read_stream, write_stream):
        # 3. Create ClientSession within its own async with block
        #    Initialization happens automatically upon entering
        async with ClientSession(
            read_stream,
            write_stream,
            # Optional: Provide client info & callbacks
            client_info=types.Implementation(name="MyPyClient", version="0.1.0")
            # sampling_callback=..., list_roots_callback=... etc.
        ) as session:
            print("Connected!")
            # Access server info (available after __aenter__ completes initialize)
            # Note: Python SDK doesn't seem to expose server caps/info as directly
            #       as the TS SDK post-initialization via properties.

            # ... proceed with interactions using 'session' ...

async def main():
    try:
        await run()
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    anyio.run(main)

```

**Key Handshake Steps (Internal):**

1.  Client sends `initialize` request with its info and capabilities.
2.  Server responds with its info, capabilities, and chosen protocol version.
3.  Client validates the server's response (especially the protocol version).
4.  Client sends `notifications/initialized`.
5.  Connection is ready for use.

Both SDKs store the negotiated server capabilities, which might be used internally (or exposed, more clearly in TS) to check if certain operations are supported before attempting them.

### Making Requests: Interacting with Primitives

Once connected, clients use methods provided by `Client` (TS) or `ClientSession` (Python) to interact with the server's Resources, Tools, and Prompts. The SDKs abstract away the need to manually construct JSON-RPC request objects.

**Listing Primitives:**

```typescript
// TypeScript
async function listItems(client: Client) {
  try {
    const toolsResult = await client.listTools();
    console.log("Tools:", toolsResult.tools.map(t => t.name));

    const resourcesResult = await client.listResources();
    console.log("Resources:", resourcesResult.resources.map(r => r.uri));

    const promptsResult = await client.listPrompts();
    console.log("Prompts:", promptsResult.prompts.map(p => p.name));
  } catch (error) {
    console.error("Error listing items:", error);
  }
}
```

```python
# Python
async def list_items(session: ClientSession):
    try:
        tools_result = await session.list_tools()
        print("Tools:", [t.name for t in tools_result.tools])

        resources_result = await session.list_resources()
        print("Resources:", [r.uri for r in resources_result.resources])

        prompts_result = await session.list_prompts()
        print("Prompts:", [p.name for p in prompts_result.prompts])
    except McpError as e:
        print(f"Error listing items: {e.error.message}")
    except Exception as e:
        print(f"Unexpected error listing items: {e}")
```

**Calling a Tool:**

```typescript
// TypeScript
async function callMyTool(client: Client) {
  try {
    const result = await client.callTool({
      name: "calculate_bmi",
      arguments: { weightKg: 70, heightM: 1.75 }
    });
    console.log("Tool Result:", result.content);
  } catch (error) {
    console.error("Error calling tool:", error);
  }
}
```

```python
# Python
async def call_my_tool(session: ClientSession):
    try:
        result = await session.call_tool(
            "calculate_bmi",
            arguments={"weightKg": 70, "heightM": 1.75}
        )
        print("Tool Result:", result.content)
    except McpError as e:
        print(f"Error calling tool: {e.error.message}")
    except Exception as e:
        print(f"Unexpected error calling tool: {e}")
```

**Reading a Resource:**

```typescript
// TypeScript
async function readMyResource(client: Client) {
  try {
    const result = await client.readResource({ uri: "config://myapp" });
    console.log("Resource Content:", result.contents);
  } catch (error) {
    console.error("Error reading resource:", error);
  }
}
```

```python
# Python
from pydantic import AnyUrl

async def read_my_resource(session: ClientSession):
    try:
        result = await session.read_resource(AnyUrl("config://myapp"))
        print("Resource Content:", result.contents)
    except McpError as e:
        print(f"Error reading resource: {e.error.message}")
    except Exception as e:
        print(f"Unexpected error reading resource: {e}")
```

**Getting a Prompt:**

```typescript
// TypeScript
async function getMyPrompt(client: Client) {
  try {
    const result = await client.getPrompt({
       name: "review_code",
       arguments: { code: "print('hello')" }
    });
    console.log("Prompt Messages:", result.messages);
  } catch (error) {
    console.error("Error getting prompt:", error);
  }
}
```

```python
# Python
async def get_my_prompt(session: ClientSession):
    try:
        result = await session.get_prompt(
            "review_code",
            arguments={"code": "print('hello')"}
        )
        print("Prompt Messages:", result.messages)
    except McpError as e:
        print(f"Error getting prompt: {e.error.message}")
    except Exception as e:
        print(f"Unexpected error getting prompt: {e}")
```

In both SDKs, the methods return Promises (TS) or awaitables (Python) that resolve to objects parsed according to the expected result type schema (e.g., `ListToolsResult`, `CallToolResult`). If the server returns a JSON-RPC error, the promise/awaitable rejects with an `McpError`.

### Handling Responses and Errors

As seen above, successful responses are returned as parsed objects (Zod-validated in TS, Pydantic-validated in Python). Errors are raised as exceptions:

*   **TypeScript:** Rejects Promises, typically with an `McpError` containing the `code`, `message`, and optional `data` from the server's error response. Network or timeout errors might raise different error types.
*   **Python:** Raises an `McpError` (from `src/mcp/shared/exceptions.py`), which wraps the `ErrorData` Pydantic model. Network or timeout errors might raise `anyio` or `httpx` exceptions depending on the transport.

Standard `try...catch` (TS) or `try...except` (Python) blocks are used for error handling.

### Receiving Server Notifications

MCP isn't just request-response; servers can proactively send notifications to clients (e.g., logging messages, resource updates, progress updates). Clients need a way to listen for and react to these.

**TypeScript (`setNotificationHandler`):**

The `Client` class uses `setNotificationHandler`. You provide the Zod schema for the notification you want to handle and a callback function.

```typescript
import { LoggingMessageNotificationSchema } from "@modelcontextprotocol/sdk/types.js";

// Assuming 'client' is an initialized Client instance

client.setNotificationHandler(
  LoggingMessageNotificationSchema, // Schema to match
  async (notification) => { // Callback receives validated notification
    console.log(`[SERVER LOG - ${notification.params.level}]:`, notification.params.data);
  }
);

// Fallback for unhandled notifications
client.fallbackNotificationHandler = async (notification) => {
  console.warn("Received unhandled notification:", notification.method);
};
```

**Python (Constructor Callbacks):**

The `ClientSession` constructor accepts optional callback functions for specific server-initiated interactions.

```python
from mcp import types
from mcp.client.session import ClientSession # ... other imports

async def handle_logging(params: types.LoggingMessageNotificationParams) -> None:
    print(f"[SERVER LOG - {params.level}]:", params.data)

async def handle_unhandled(message: Any) -> None: # Can inspect message type
    if isinstance(message, types.ServerNotification):
        print(f"Received unhandled notification: {message.root.method}")
    elif isinstance(message, Exception):
        print(f"Received error from transport: {message}")
    # ... handle requests if needed for client-acting-as-server

async def run_client_with_logging():
    # ... setup transport streams (read_stream, write_stream) ...
    async with ClientSession(
        read_stream,
        write_stream,
        logging_callback=handle_logging,      # Specific callback
        message_handler=handle_unhandled     # Generic fallback
    ) as session:
        await session.initialize() # Already done by __aenter__ but explicit call is fine
        # ... interact ...

# Note: ClientSession also accepts sampling_callback and list_roots_callback
# for handling *requests* FROM the server, acting briefly as a server itself.
```

Python's approach uses specific callbacks passed during initialization, plus a general `message_handler` for anything else. TypeScript uses a more dynamic registration model with `setNotificationHandler`.

### Advanced Client Features

Both SDKs support more advanced client-side operations, which we'll explore further in later posts:

*   **Timeouts:** Specifying timeouts for requests.
*   **Cancellation:** Using `AbortSignal` (TS) or `anyio.CancelScope` (implied, Python) to cancel long-running requests.
*   **Progress:** Receiving progress updates for requests (`onprogress` option in TS `client.request`).
*   **Authentication:** Handling OAuth flows (more built-in helpers in TS).

### Comparison: Client APIs

| Feature                | `Client` (TypeScript)                | `ClientSession` (Python)                     | Notes                                                                            |
| :--------------------- | :----------------------------------- | :------------------------------------------- | :------------------------------------------------------------------------------- |
| **Instantiation**      | `new Client(...)`                    | `ClientSession(...)` (within `async with`) | TS is standard class instantiation; Python uses async context management.          |
| **Connection**         | `client.connect(transport)`          | `async with transport_factory(...) as (r,w): async with ClientSession(r,w)` | TS takes transport *instance*; Python uses transport *factory functions* yielding streams. Initialization is implicit in Python's `async with`. |
| **API Style**          | Methods on `Client` instance         | Methods on `session` object (from `async with`) | Both provide clear methods for MCP operations.                                 |
| **Notification Handling**| `setNotificationHandler(schema, cb)` | Callbacks passed to `ClientSession` constructor | TS allows dynamic registration per type; Python uses pre-defined callback slots. |
| **Server->Client Req** | `setRequestHandler` (for sampling/roots) | Specific callbacks (`sampling_callback`, `list_roots_callback`) in constructor | Both support client acting briefly as a server for specific methods.         |

### Conclusion: Enabling Intelligent Interactions

The client-side components of the MCP SDKs (`Client` in TS, `ClientSession` in Python) provide the essential tools for applications to consume MCP services. They manage the connection lifecycle, abstract the complexities of the JSON-RPC protocol, and offer straightforward methods for interacting with server-provided Tools, Resources, and Prompts. Furthermore, they provide mechanisms for handling asynchronous server-sent notifications, enabling responsive and dynamic user experiences.

By simplifying client implementation, the SDKs empower developers to build applications – from chatbots to IDE extensions – that can intelligently leverage the context and capabilities exposed by a growing ecosystem of MCP servers.

Next, we'll delve into the crucial layer connecting clients and servers: **Blog 6: Bridging Worlds - Transport Deep Dive**. We'll compare how Stdio, SSE, and WebSocket transports are implemented in both SDKs.

---