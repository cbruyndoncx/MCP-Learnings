---
title: "Blog 3: Building MCP Servers the Easy Way: McpServer (TS) vs. FastMCP (Python)"
draft: false
---
## Blog 3: Building MCP Servers the Easy Way: McpServer (TS) vs. FastMCP (Python)

**Series:** Deep Dive into the Model Context Protocol SDKs (TypeScript & Python)
**Post:** 3 of 10

In the [previous post](blog-2.md), we explored the type systems (Zod and Pydantic) that define the precise language of the Model Context Protocol (MCP) within the TypeScript and Python SDKs. These types ensure reliable communication, but directly implementing the request/response handling logic for every MCP method can still be complex.

This is where the high-level server APIs come in. Both SDKs offer abstractions designed to drastically simplify the process of creating MCP servers. Developers can focus on *what* functionality (Tools) or data (Resources, Prompts) they want to expose, letting the SDK handle the underlying protocol boilerplate.

Today, we'll compare the primary high-level server abstractions:

*   **TypeScript:** The `McpServer` class (`src/server/mcp.ts`)
*   **Python:** The `FastMCP` class (`src/mcp/server/fastmcp/server.py`)

### TypeScript: Declarative Registration with `McpServer`

The TypeScript SDK provides the `McpServer` class, which wraps the lower-level `Server` (more on that in the next post). Its core philosophy is *declarative registration* using specific methods for each MCP primitive.

**Initialization:**

```typescript
// TypeScript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

// Create the server instance
const mcpServer = new McpServer({
  name: "MyTypeScriptServer",
  version: "1.0.0"
}, {
  // Optional: Define server capabilities upfront
  capabilities: {
    logging: {}, // Enable logging capability
    // resources, tools, prompts capabilities are often added
    // implicitly when you register items below.
  }
});
```

**Registering Primitives:**

You add functionality by calling methods on the `mcpServer` instance:

1.  **Tools (`.tool()`):**
    *   Exposes functions as callable actions for the LLM client.
    *   Handles input validation using Zod schemas.
    *   Supports overloads for descriptions and [annotations](https://spec.modelcontextprotocol.io/main/basic/primitives.html#tool-annotations) (hints about the tool's behavior).

    ```typescript
    import { z } from "zod";

    // Tool with no arguments
    mcpServer.tool("get_time", async () => ({
      content: [{ type: "text", text: new Date().toISOString() }]
    }));

    // Tool with description and Zod schema for arguments
    const bmiTool = mcpServer.tool(
      "calculate_bmi", // Name
      "Calculates Body Mass Index", // Description
      { // Zod schema for arguments
        weightKg: z.number().describe("Weight in kilograms"),
        heightM: z.number().describe("Height in meters")
      },
      { // Optional Annotations
         title: "BMI Calculator",
         readOnlyHint: true // This tool doesn't change anything
      },
      // Async callback function receiving validated arguments
      async ({ weightKg, heightM }) => {
        const bmi = weightKg / (heightM * heightM);
        return { content: [{ type: "text", text: String(bmi) }] };
      }
    );
    ```

2.  **Resources (`.resource()`):**
    *   Exposes data to the LLM client.
    *   Can be a static resource (fixed URI) or dynamic (using `ResourceTemplate`).
    *   Callbacks receive URI details and matched template variables.

    ```typescript
    import { ResourceTemplate } from "@modelcontextprotocol/sdk/server/mcp.js";

    // Static resource
    mcpServer.resource(
      "app_config", // Internal name
      "config://myapp", // Fixed URI
      { mimeType: "application/json" }, // Metadata
      async (uri) => ({ // Callback
        contents: [{ uri: uri.href, text: JSON.stringify({ theme: "dark" }) }]
      })
    );

    // Dynamic resource using a template
    const userProfileResource = mcpServer.resource(
      "user_profile", // Internal name
      new ResourceTemplate("users://{userId}/profile"), // URI Template
      { description: "Fetches user profile data" }, // Metadata
      // Callback receives URI and matched 'userId' variable
      async (uri, { userId }) => {
        // const profileData = await fetchUserProfileFromDB(userId);
        const profileData = `Profile for ${userId}`;
        return { contents: [{ uri: uri.href, text: profileData }] };
      }
    );
    ```

3.  **Prompts (`.prompt()`):**
    *   Defines reusable interaction templates.
    *   Can accept arguments defined by a Zod schema.
    *   Callback returns a list of `PromptMessage` objects.

    ```typescript
    // Prompt without arguments
    mcpServer.prompt("help_overview", async () => ({
      messages: [{ role: "user", content: { type: "text", text: "Provide a general overview of help topics." } }]
    }));

    // Prompt with arguments
    const codeReviewPrompt = mcpServer.prompt(
      "review_code", // Name
      "Generates a code review request", // Description
      { code: z.string().describe("The code snippet to review") }, // Zod Schema
      // Callback receives validated 'code' argument
      ({ code }) => ({
        messages: [{
          role: "user",
          content: { type: "text", text: `Please review this code:\n\n${code}` }
        }]
      })
    );
    ```

**Dynamic Updates:**

A key feature highlighted in the TS SDK documentation is the ability to modify the server *after* it has connected to a transport. The `.tool()`, `.resource()`, and `.prompt()` methods return handles (`RegisteredTool`, etc.) that have methods like `.enable()`, `.disable()`, `.update(...)`, and `.remove()`. Calling these automatically triggers `listChanged` notifications to connected clients.

```typescript
// Example: Disable the BMI tool initially
bmiTool.disable();

// Later... enable it based on some condition
if (userHasPremiumAccess) {
  bmiTool.enable(); // Client gets notified
}

// Update the prompt's callback or schema
codeReviewPrompt.update({ /* new options */ });

// Remove a resource entirely
userProfileResource.remove();
```

**Connecting:**

Finally, the server needs to be connected to a transport (details in later posts):

```typescript
// Example using Stdio
const transport = new StdioServerTransport();
await mcpServer.connect(transport); // Starts listening
```

### Python: Ergonomic Decorators with `FastMCP`

The Python SDK introduces `FastMCP` (`src/mcp/server/fastmcp/server.py`), designed for a more Pythonic, developer-friendly experience using decorators. It wraps the lower-level `Server` internally.

**Initialization:**

```python
# Python
from mcp.server.fastmcp import FastMCP, Context

# Create the server instance
# Settings can be passed here or via env vars (FASTMCP_*)
mcp = FastMCP(
    name="MyPythonServer",
    instructions="Server usage instructions...",
    dependencies=["pandas"] # Optional: Declare runtime dependencies
)
```

**Registering Primitives:**

`FastMCP` uses decorators applied directly to your Python functions:

1.  **Tools (`@mcp.tool()`):**
    *   Decorated functions become MCP tools.
    *   Python type hints are automatically parsed (using Pydantic via `func_metadata`) to generate the `inputSchema`. Pydantic `Field` can be used for descriptions/defaults.
    *   Optional `Context` object can be injected via type hint for access to logging, progress, etc.

    ```python
    from typing import Annotated
    from pydantic import Field

    # Basic tool
    @mcp.tool()
    def add(a: int, b: int) -> int:
        """Adds two numbers together.""" # Docstring becomes description
        return a + b

    # Tool with Field descriptions and context injection
    @mcp.tool()
    def complex_tool(
        query: Annotated[str, Field(description="The search query")],
        limit: int = 10,
        ctx: Context | None = None # Context injection via type hint
    ) -> list[str]:
        """Performs a complex search."""
        if ctx:
            ctx.info(f"Running search for '{query}' with limit {limit}")
        # ... perform search ...
        return ["result1", "result2"]
    ```

2.  **Resources (`@mcp.resource()`):**
    *   Decorated functions provide resource content.
    *   The decorator takes the URI (static or template).
    *   Function parameters *must* match URI template parameters if it's dynamic.
    *   Return type determines content (str -> text, bytes -> binary, others -> JSON).

    ```python
    # Static resource
    @mcp.resource("config://myapp", mime_type="application/json")
    def get_config() -> dict:
        """Returns application configuration."""
        return {"theme": "dark"}

    # Dynamic resource (template)
    @mcp.resource("users://{user_id}/profile")
    def get_user_profile(user_id: str) -> str: # 'user_id' matches URI
        """Fetches profile data for a specific user."""
        # profile_data = db.fetch_user(user_id)
        return f"Profile data for user {user_id}"
    ```

3.  **Prompts (`@mcp.prompt()`):**
    *   Decorated functions generate prompt messages.
    *   Function parameters define prompt arguments.
    *   Can return strings, `Message` objects, or lists thereof.

    ```python
    from mcp.server.fastmcp.prompts import UserMessage, AssistantMessage

    # Basic prompt returning a string
    @mcp.prompt()
    def basic_greeting(name: str) -> str:
        """Generates a simple greeting prompt."""
        return f"Please greet {name} warmly."

    # Prompt returning structured messages
    @mcp.prompt()
    def multi_turn_debug(error_log: str) -> list[Message]:
        """Starts a debugging session."""
        return [
            UserMessage(f"I encountered this error:\n{error_log}"),
            AssistantMessage("Okay, I can help. What steps did you take before this error occurred?")
        ]
    ```

**Lifespan Management:**

`FastMCP` supports ASGI-style `lifespan` context managers for setup/teardown logic:

```python
from contextlib import asynccontextmanager
from collections.abc import AsyncIterator

@dataclass
class AppState:
    db_connection: Any # Your DB connection type

@asynccontextmanager
async def app_lifespan(server: FastMCP) -> AsyncIterator[AppState]:
    print("Server startup: Connecting to DB...")
    # connection = await connect_db()
    connection = "fake_db_connection"
    state = AppState(db_connection=connection)
    try:
        yield state # State is accessible via ctx.request_context.lifespan_context
    finally:
        print("Server shutdown: Disconnecting DB...")
        # await connection.close()

mcp = FastMCP("MyAppWithLifespan", lifespan=app_lifespan)

# Tool accessing lifespan state
@mcp.tool()
def query_data(query: str, ctx: Context) -> list:
    db_conn = ctx.request_context.lifespan_context.db_connection
    # results = await db_conn.fetch(query)
    print(f"Querying with {db_conn}: {query}")
    return [{"result": "dummy"}]
```

**Running:**

`FastMCP` provides a simple `run()` method:

```python
if __name__ == "__main__":
    mcp.run() # Defaults to stdio transport
    # Or: mcp.run(transport="sse")
```

### Comparison: `McpServer` vs. `FastMCP`

| Feature                | `McpServer` (TypeScript)                     | `FastMCP` (Python)                                   | Notes                                                                                                 |
| :--------------------- | :------------------------------------------- | :----------------------------------------------------- | :---------------------------------------------------------------------------------------------------- |
| **Registration Style** | Method calls (`.tool()`, `.resource()`)    | Decorators (`@mcp.tool()`, `@mcp.resource()`)      | TS uses explicit registration; Python leverages decorators for a more concise, idiomatic feel.        |
| **Parameter Handling** | Explicit Zod Schemas                         | Type Hint Inference + Pydantic `Field`               | TS requires defining schemas separately; Python infers schemas from function signatures, potentially faster for simple cases but might hide complexity. |
| **Context Access**     | Passed via `RequestHandlerExtra` (low-level) | Optional `Context` injection via type hint         | Python's `FastMCP` provides a dedicated, user-friendly `Context` object directly in the high-level API. |
| **Dynamic Updates**    | Explicit via handles (`.enable()`, `.update()`) | Less emphasized in docs/examples for `FastMCP`       | TS API makes post-connection updates explicit. Python's `FastMCP` might require interacting with the underlying low-level server or managers for this. |
| **Configuration**      | Constructor options                          | `Settings` model, env vars, constructor kwargs       | Python offers more flexible configuration via Pydantic settings and environment variables.            |
| **Dependencies**       | `package.json`                               | `dependencies` kwarg, `pyproject.toml`               | Python's `FastMCP` allows declaring runtime dependencies needed by tools/resources directly.          |
| **Web Integration**    | Requires manual Express/etc. setup         | Built-in ASGI app (`sse_app()`), Uvicorn integration | `FastMCP` provides easier integration with the Python web ecosystem (ASGI).                           |

### End-User Impact: Streamlined Development = Richer AI

Why do these high-level APIs matter to someone *using* an MCP-powered application?

1.  **Faster Integration:** `McpServer` and `FastMCP` significantly reduce the effort needed for developers to expose application capabilities or data to LLMs. This means more applications can gain contextual AI features more quickly.
2.  **Consistency:** By providing structured ways to define tools and resources (schemas in TS, type hints/Pydantic in Python), the SDKs encourage consistent definitions, leading to more predictable behavior when an AI client interacts with different servers.
3.  **Focus on Value:** Developers spend less time on protocol plumbing and more time defining *useful* tools and *relevant* resources, resulting in AI assistants that are genuinely more helpful and context-aware.
4.  **Enabling Complex Apps:** Features like context injection and lifespan management (especially prominent in `FastMCP`) make it feasible to build sophisticated servers that manage state or external connections, unlocking more powerful use cases for the end-user's AI.

### Conclusion

Both `McpServer` (TypeScript) and `FastMCP` (Python) serve as powerful, developer-friendly gateways to building MCP servers. They abstract away much of the underlying protocol complexity, allowing developers to focus on exposing functionality and data. While TypeScript's `McpServer` uses explicit method calls and Zod schemas, Python's `FastMCP` leans into decorators and type-hint inference for a more concise, Pythonic feel. Both successfully lower the barrier to entry for creating context-aware AI applications.

While these high-level APIs are sufficient for many use cases, sometimes finer control is needed. In the next post, we'll lift the hood and examine the lower-level `Server` classes in both SDKs to understand the core protocol handling and explore more advanced customization options.

---
