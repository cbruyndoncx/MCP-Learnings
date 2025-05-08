---
title: "Blog 9: Beyond the Basics - Advanced MCP SDK Capabilities"
draft: false
---
## Blog 9: Beyond the Basics - Advanced MCP SDK Capabilities

**Series:** Deep Dive into the Model Context Protocol SDKs (TypeScript & Python)
**Post:** 9 of 10

We've covered a lot of ground in this series, exploring the [core types](blog-2.md), [server APIs](blog-3.md), [low-level foundations](blog-4.md), [client architecture](blog-5.md), various [transports](blog-6.md), [Streamable HTTP](blog-7.md), and [authentication](blog-8.md). Now, it's time to delve into some of the more advanced features and capabilities offered by the TypeScript and Python Model Context Protocol (MCP) SDKs that enable more sophisticated and dynamic applications.

These features often differentiate the SDKs and highlight design choices specific to each language ecosystem. We'll explore:

*   **Dynamic Server Updates (TS):** Modifying server capabilities *after* connection.
*   **Context Injection (Python `FastMCP`):** Accessing request/server state within handlers.
*   **Autocompletion (TS):** Providing suggestions for resource/prompt arguments.
*   **CLI Tooling (Python):** The `mcp` command for development and Claude Desktop integration.
*   **Resumability (TS Streamable HTTP):** Recovering from disconnections.

### Dynamic Server Capabilities (TypeScript Focus)

One of the powerful, explicitly documented features in the TypeScript `McpServer` is the ability to modify the available Tools, Resources, and Prompts *while the server is running and connected* to clients.

**How it Works:**

When you register a primitive using `mcpServer.tool()`, `.resource()`, or `.prompt()`, the method returns a handle object (`RegisteredTool`, `RegisteredResource`, `RegisteredPrompt`). These handles expose methods to manage the lifecycle and definition of that primitive *after* the initial registration and connection:

*   **`.enable()` / `.disable()`:** Toggles the visibility of the primitive. Disabled items won't appear in `listTools`, `listResources`, etc.
*   **`.update({...})`:** Allows changing aspects of the primitive, such as:
    *   The callback function (`callback`).
    *   The input schema (`paramsSchema` for tools, `argsSchema` for prompts).
    *   Metadata like `description` or `annotations`.
    *   For resources, the underlying URI or `ResourceTemplate`.
*   **`.remove()`:** Completely unregisters the primitive from the server.

**The Notification Link:**

Crucially, whenever you call `.enable()`, `.disable()`, `.update()`, or `.remove()` on a registered handle *after* the `McpServer` is connected to a transport, the server automatically sends the corresponding `notifications/.../list_changed` message (e.g., `notifications/tools/list_changed`) to all connected clients. This informs clients that they should refresh their list of available primitives.

```typescript
// TypeScript Dynamic Example
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
// ... other imports ...

const mcpServer = new McpServer(/* ... */);

// Register a tool, get its handle
const sensitiveTool = mcpServer.tool(
  "admin_action",
  { targetId: z.string() },
  async ({ targetId }) => { /* ... perform action ... */ }
);

// Initially disabled
sensitiveTool.disable();

// Connect the server
const transport = /* ... create transport ... */;
await mcpServer.connect(transport);

// Later, based on authentication or state change:
async function checkAuthAndEnableTool(authInfo: AuthInfo | undefined) {
  if (authInfo?.scopes.includes("admin")) {
    if (!sensitiveTool.enabled) {
      console.log("Admin connected, enabling sensitive tool...");
      sensitiveTool.enable(); // Client receives notifications/tools/list_changed
    }
  } else {
    if (sensitiveTool.enabled) {
      console.log("Non-admin connected, disabling sensitive tool...");
      sensitiveTool.disable(); // Client receives notifications/tools/list_changed
    }
  }
}

// Example Update: Change the schema for a prompt
const myPrompt = mcpServer.prompt("my_prompt", { oldArg: z.string() }, /* ... */);
// ... server connected ...
myPrompt.update({
  description: "Updated description",
  argsSchema: { newArg: z.number() }, // Schema changed!
  callback: ({ newArg }) => { /* ... new logic ... */ }
}); // Client receives notifications/prompts/list_changed
```

**Python `FastMCP`:**

The documentation and examples for Python's `FastMCP` don't explicitly showcase this dynamic update pattern with handles in the same way. While the underlying low-level `Server` *can* send `list_changed` notifications manually (`server.send_tool_list_changed()`, etc.), dynamically altering the registered decorators after startup isn't the standard pattern. Achieving similar dynamic behavior in `FastMCP` might involve:

*   Using conditional logic *within* the tool/resource/prompt functions based on server state.
*   Potentially interacting with the internal managers (`_tool_manager`, etc.), though this is less documented and likely less stable than the TS handle approach.
*   Manually sending `list_changed` notifications via the low-level server instance if internal state affecting lists changes.

**End-User Nuance:** Dynamic capabilities allow AI applications to adapt intelligently. An assistant might gain new tools after a user logs in or installs a plugin, or resources might appear/disappear based on the currently active project – all communicated seamlessly via MCP notifications.

### Context Injection (Python `FastMCP` Focus)

Python's `FastMCP` offers a very convenient way to access request-specific information and server capabilities within your handler functions: the `Context` object.

**How it Works:**

You simply add a parameter to your decorated function and type-hint it as `Context`. `FastMCP` automatically injects the appropriate context instance during the request.

```python
# Python FastMCP Context Example
from mcp.server.fastmcp import FastMCP, Context
from mcp.server.lowlevel.server import LifespanResultT # For lifespan context typing
from mcp.server.session import ServerSessionT # For session typing

mcp = FastMCP("MyContextServer")

@mcp.tool()
async def complex_operation(item_id: str, ctx: Context) -> str:
    # Access lifespan state (if lifespan manager is used)
    # db_conn = ctx.request_context.lifespan_context.db_connection

    # Log messages to the client
    ctx.info(f"Starting operation for item {item_id} (Request ID: {ctx.request_id})")

    # Report progress
    await ctx.report_progress(progress=1, total=3)

    # Read related resource
    try:
        resource_iter = await ctx.read_resource(f"items://{item_id}/details")
        details = "".join([r.content for r in resource_iter]) # Assuming text content
        ctx.debug(f"Read details: {details[:50]}...")
    except Exception as e:
        await ctx.error(f"Failed to read resource: {e}")
        return "Error fetching details"

    await ctx.report_progress(progress=2, total=3)
    # ... perform more work ...
    await ctx.report_progress(progress=3, total=3)

    return f"Operation complete for {item_id}"

# Get the underlying session for advanced features
@mcp.tool()
async def check_client_caps(ctx: Context) -> bool:
    session: ServerSessionT = ctx.session # Access the low-level session
    if session.client_params:
        print("Client connected:", session.client_params.clientInfo)
        return session.check_client_capability(types.ClientCapabilities(sampling={}))
    return False
```

**TypeScript Context:**

While `McpServer` doesn't have a single unified `Context` object like `FastMCP`, the *low-level* request handlers (`Server.setRequestHandler`) receive the `RequestHandlerExtra` object, which contains much of the same information (`signal`, `sessionId`, `requestId`, `authInfo`, `_meta`) and helper methods (`sendNotification`, `sendRequest`). If using `McpServer`, the callbacks for `.tool()`, `.resource()`, and `.prompt()` also receive this `extra` object as their last argument.

**Comparison:** Python's `Context` object injected via type hint is arguably more ergonomic and discoverable for the common high-level use case within `FastMCP`. TypeScript requires passing the `extra` object explicitly in the high-level API callbacks or accessing it directly in low-level handlers.

**End-User Nuance:** Context allows servers to provide better feedback (logging, progress) and perform more complex, state-aware operations, leading to more responsive and capable AI interactions for the user.

### Autocompletion (TypeScript Focus)

The TypeScript SDK includes a mechanism for providing autocompletion suggestions for arguments within Resource Templates and Prompts.

**How it Works:**

*   **`Completable` (`src/server/completable.ts`):** A wrapper around a Zod schema (`completable(z.string(), ...)`) that attaches a `complete` callback function.
*   **Registration:** You use this `Completable` schema when defining arguments for a `ResourceTemplate` or a `McpServer.prompt`.
*   **Handling:** `McpServer` automatically registers a handler for the `completion/complete` MCP request. When a client sends this request for a specific argument of a prompt or resource template, the server finds the registered `Completable` schema and invokes its `complete` callback (passing the current partial value entered by the user).
*   **Response:** The server formats the suggestions returned by the callback into a `CompleteResult` message.

```typescript
// TypeScript Autocompletion Example
import { completable } from "@modelcontextprotocol/sdk/server/completable.js";
import { ResourceTemplate } from "@modelcontextprotocol/sdk/server/mcp.js";

const allCategories = ["books", "movies", "music", "games"];

// Resource Template with completable argument
mcpServer.resource(
  "items_by_category",
  new ResourceTemplate("items://{category}", {
    list: undefined,
    // Define completion logic for the 'category' variable
    complete: {
      category: (partialValue) =>
        allCategories.filter(cat => cat.startsWith(partialValue))
    }
  }),
  async (uri, { category }) => { /* ... fetch items ... */ }
);

// Prompt with completable argument
mcpServer.prompt(
  "search_items",
  {
    // Wrap the Zod schema with completable
    category: completable(
      z.enum(["books", "movies", "music", "games"]), // Base schema
      (partialValue) => // Completion callback
        allCategories.filter(cat => cat.startsWith(partialValue))
    ).describe("The category to search within"),
    query: z.string()
  },
  async ({ category, query }) => { /* ... create prompt messages ... */ }
);
```

**Python Equivalent:**

The Python SDK (`FastMCP` or low-level `Server`) doesn't appear to have a direct, built-in equivalent to the `Completable` wrapper and automatic `completion/complete` handler registration. Implementing autocompletion would likely require:

1.  Manually registering a handler for `completion/complete` using the low-level `@server.completion()` decorator (if available, or `@server.request_handler` otherwise).
2.  Storing metadata about which arguments are completable and their associated completion functions alongside the tool/prompt/resource definitions.
3.  Implementing the logic within the `completion/complete` handler to look up the correct completion function based on the request's `ref` and `argument` parameters and call it.

**End-User Nuance:** Autocompletion significantly improves the usability of complex tools or resources with predefined argument values (like categories, file paths, user names), guiding the user (or the LLM) towards valid inputs.

### CLI Tooling (Python Focus)

The Python SDK ships with a powerful command-line tool, `mcp`, built using `typer`. This tool streamlines common development and deployment workflows, especially for users of the Claude Desktop application.

**Key Commands:**

*   **`mcp run <file_spec>`:** Directly runs an MCP server defined in a Python file (e.g., `python my_server.py` equivalent, but integrated). It imports and calls the `.run()` method on the discovered server object (`mcp`, `server`, or `app` by default, or specified via `file:object`).
*   **`mcp dev <file_spec> [--with <dep>] [--with-editable <path>]`:** Runs the server in development mode, typically launching it alongside the [MCP Inspector](https://github.com/modelcontextprotocol/inspector) tool (`npx @modelcontextprotocol/inspector ...`). It uses `uv run --with ...` internally to manage a temporary virtual environment, installing the base `mcp` package plus any declared server dependencies (`--with`) or editable installs (`--with-editable`).
*   **`mcp install <file_spec> [--name <name>] [--with <dep>] [--with-editable <path>] [-v KEY=VAL] [-f .env]`:** This is the key integration point with Claude Desktop.
    *   It locates the Claude Desktop configuration file (`claude_desktop_config.json`).
    *   It adds or updates an entry for the specified MCP server.
    *   It constructs the correct `uv run [...] mcp run <file_spec>` command, including necessary `--with` and `--with-editable` flags based on declared/provided dependencies.
    *   It allows setting environment variables (`-v` or `-f`) specific to that server entry in the Claude config.
    *   The `server_name` defaults intelligently (server's `.name` attribute or file stem).

**Implementation (`src/mcp/cli/`):**

*   `cli.py`: Defines the `typer` application and commands.
*   `claude.py`: Contains logic for finding the Claude config path (`get_claude_config_path`) and updating the JSON configuration (`update_claude_config`).

**TypeScript Equivalent:**

The TS SDK has a much simpler `src/cli.ts`, which primarily acts as a basic command-line runner for example client/server setups, mainly using the Stdio transport. It lacks the sophisticated environment management and Claude Desktop integration of the Python CLI.

**End-User/Developer Nuance:** The Python `mcp` CLI significantly enhances the developer workflow, especially for `FastMCP` users and those targeting Claude Desktop. `mcp dev` provides an integrated testing environment, while `mcp install` makes deploying local or custom servers to the Claude Desktop app trivial, handling dependency installation automatically via `uv`.

### Resumability (TypeScript Streamable HTTP Focus)

As detailed in Blog 7, resumability is a built-in feature of the TypeScript SDK's `StreamableHTTPServerTransport` when configured with an `EventStore`. It ensures clients can recover from disconnections during long-running operations without missing messages. While not a *separate* API feature, it's an advanced capability tied to the transport choice. The Python SDK's SSE transport lacks this built-in mechanism.

### Conclusion

The advanced capabilities of the MCP SDKs showcase their potential beyond simple request-response interactions. TypeScript's `McpServer` provides explicit control over the dynamic lifecycle of server primitives and built-in support for argument autocompletion. Python's `FastMCP`, coupled with its `mcp` CLI, offers a highly ergonomic development experience with seamless context injection and effortless integration into environments like Claude Desktop. Resumability, currently a key feature of TypeScript's Streamable HTTP transport, enhances robustness for web-based applications.

Understanding these advanced features allows developers to build more sophisticated, dynamic, user-friendly, and resilient MCP applications.

In our final post, we'll synthesize everything we've learned, comparing the overall developer experience, discussing ideal use cases for each SDK, and looking towards the future of MCP.

---
