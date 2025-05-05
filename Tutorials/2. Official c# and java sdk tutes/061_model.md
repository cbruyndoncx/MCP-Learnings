Okay, here is a detailed draft for the next blog post (Blog 12 in the extended series), targeting advanced users and focusing on Resources and Resource Templates across the four SDKs.

---

## Blog 12: Advanced Resource Management - Static Data, URI Templates, and Content Handling in MCP SDKs

**Series:** Deep Dive into the Model Context Protocol SDKs
**Post:** 12 of 10 (Advanced Topics)

In our ongoing exploration of the Model Context Protocol (MCP) SDKs, we've thoroughly examined [server](link-to-post-3)/[client](link-to-post-5) architecture, [transports](link-to-post-6)/[framework integration](link-to-post-8), [authentication](link-to-post-8), and most recently, the intricacies of defining and executing [Tools](link-to-post-11). Now, we turn our focus to the second core MCP primitive: **Resources**.

Resources are the mechanism by which MCP servers provide contextual data *to* clients (and ultimately, the LLM). This could be anything from the content of a file, the results of a database query, real-time sensor data, or application-specific state. Effectively managing and exposing resources is critical for enabling context-aware AI.

This advanced post dives into the nuances of Resource definition and handling across the TypeScript, Python, C#, and Java SDKs, comparing how they manage:

1.  **Static vs. Dynamic Resources:** Fixed URIs vs. URI Templates (RFC 6570).
2.  **Handler Implementation:** Function signatures, context access, and parameter binding.
3.  **Content Representation:** Handling text (`TextResourceContents`) vs. binary (`BlobResourceContents`) data and MIME types.
4.  **Discovery:** How clients learn about available resources (`list_resources`) and templates (`list_resource_templates`).
5.  **Advanced Features:** Argument completion for templates (where available).

### Static Resources: The Simplest Case

Exposing data at a fixed, known URI is the most basic resource pattern.

*   **TypeScript (`McpServer.resource()`):** Provide a string URI and a callback.
    ```typescript
    mcpServer.resource(
      "app_status",         // Internal registration name
      "status://myapp/json", // The fixed URI
      { mimeType: "application/json" }, // Metadata
      async (uri, extra) => ({ // Handler: uri is the requested URI
        contents: [{ uri: uri.href, text: JSON.stringify({ ok: true, uptime: '...' }) }]
      })
    );
    ```
*   **Python (`@mcp.resource()`):** Decorate a function with a string URI. The function name becomes the internal registration name.
    ```python
    @mcp.resource("config://defaults", mime_type="application/json")
    def get_default_config() -> dict: # Return value converted automatically
        """Returns the default app config."""
        return {"theme": "light", "fontSize": 12}
    ```
*   **C# (Handlers / Attributes):** Typically involves registering a handler delegate via `IMcpServerBuilder.WithReadResourceHandler` (checking for specific URIs) or potentially discovering resource methods via attributes (less common for *static* URIs compared to tools/prompts, but possible with convention).
    ```csharp
    // Option 1: Handler Delegate
    builder.WithReadResourceHandler(async (ctx, ct) => {
        if (ctx.Params?.Uri == "status://myapp") {
            return new ReadResourceResult { Contents = [ /*...*/ ] };
        }
        // Handle other URIs or throw NotSupportedException
    });
    // Option 2: Conceptual Attribute (if SDK supported direct resource methods)
    // [McpServerResourceType] class MyResources { [McpResource("status://myapp")] public string GetStatus() => ... }
    ```
*   **Java (Builder + Specifications):** Pass an `Async/SyncResourceSpecification` containing the `Resource` metadata (with the fixed URI) and the handler `BiFunction` to the `McpServer` builder.
    ```java
    Resource statusResourceMeta = new Resource("status://myapp", "App Status", "application/json", null, null);
    SyncResourceSpecification statusSpec = new SyncResourceSpecification(
        statusResourceMeta,
        (exchange, req) -> new ReadResourceResult(List.of(
            new TextResourceContents(req.uri(), "application/json", "{\"ok\":true}")
        ))
    );
    McpServer.sync(provider).resources(statusSpec).build();
    ```

**Comparison:** Python's decorator is the most concise for simple cases. TS requires a callback but clearly separates registration name from URI. C# and Java require more explicit handler registration/specification objects, often checking the requested URI within the handler logic.

### Dynamic Resources: Power of URI Templates (RFC 6570)

The real power comes from exposing resources whose URIs follow a pattern, defined by [RFC 6570 URI Templates](https://tools.ietf.org/html/rfc6570). Examples: `users://{userId}/profile`, `files://{path*}`.

*   **TypeScript (`ResourceTemplate`):** The SDK provides a dedicated `ResourceTemplate` class which wraps the URI template string (or an instance of the SDK's internal `UriTemplate` parser). This object is passed to `McpServer.resource()`.
    *   **Parameter Binding:** The handler callback automatically receives an object containing the *parsed* values from the URI based on the template (e.g., `{ userId: "123" }`).
    *   **URI Parsing:** Uses an internal `UriTemplate` class (`src/shared/uriTemplate.ts`) to parse templates and match incoming URIs.

    ```typescript
    import { ResourceTemplate } from "@modelcontextprotocol/sdk/server/mcp.js";

    mcpServer.resource(
      "user_profile_ts", // Internal name
      new ResourceTemplate("users://{userId}/profile/{section=details}"), // Template with default
      // Handler receives URI, parsed { userId, section }, and extra
      async (uri, { userId, section }, extra) => {
          const data = await fetchProfileSection(userId, section); // Use parsed vars
          return { contents: [{ uri: uri.href, text: data }] };
      }
    );
    ```
*   **Python (`@mcp.resource()` with template URI):** `FastMCP` automatically detects template syntax (`{...}`) in the decorator's URI string.
    *   **Parameter Binding:** If the URI is a template, the decorated function's parameters *must exactly match* the variable names in the template. Python's type hints define the expected types, and `FastMCP` handles extracting the values from the matched URI and passing them to the function.
    *   **URI Parsing:** Likely uses regex internally within the `ResourceManager` and `ResourceTemplate` (`src/mcp/server/fastmcp/resources/`) to match URIs and extract parameters based on the function signature.

    ```python
    @mcp.resource("files://{path}") # Function param must be 'path'
    def read_file(path: str, ctx: Context | None = None) -> bytes: # 'path' matches {path}
        """Reads a file, path relative to user home."""
        # VERY IMPORTANT: Sanitize 'path' to prevent traversal attacks!
        safe_path = secure_join(Path.home(), path)
        if ctx:
            ctx.info(f"Reading file: {safe_path}")
        return safe_path.read_bytes()
    ```
*   **C# (Manual Handling in Handler):** The core SDK and ASP.NET Core integration don't have built-in URI template parsing linked directly to resource handlers in the same way as TS/Python high-level APIs.
    *   **Parameter Binding:** Developers typically register a single `WithReadResourceHandler`. This handler receives the *raw* requested URI string (`requestContext.Params.Uri`). The handler logic must manually parse this URI, potentially using regex or string manipulation, to extract parameters and determine if it matches a conceptual template.
    *   **URI Parsing:** Requires manual implementation or external libraries.

    ```csharp
    // Handler registered via builder.WithReadResourceHandler(...)
    async ValueTask<ReadResourceResult> HandleReadResource(
        RequestContext<ReadResourceRequestParams> ctx, CancellationToken ct)
    {
        string requestedUri = ctx.Params?.Uri ?? "";
        // Manual matching and parsing needed
        var userMatch = Regex.Match(requestedUri, @"^users://(?<userId>[^/]+)/profile$");
        if (userMatch.Success) {
            string userId = userMatch.Groups["userId"].Value;
            // ... fetch profile for userId ...
            return new ReadResourceResult { /* ... */ };
        }
        var fileMatch = Regex.Match(requestedUri, @"^files://(?<path>.+)$");
        if (fileMatch.Success) {
            string path = fileMatch.Groups["path"].Value;
            // ... fetch file content for path (SANITIZE!) ...
            return new ReadResourceResult { /* ... */ };
        }
        throw new McpException($"Resource not found or pattern mismatch: {requestedUri}");
    }
    ```
*   **Java (Manual Handling in Handler + `McpUriTemplateManager`):** Similar to C#, the core SDK requires manual handling within the `readHandler` `BiFunction`.
    *   **Parameter Binding:** The handler receives the `ReadResourceRequest` containing the raw URI string. It must manually parse/match this.
    *   **URI Parsing:** The SDK *does* provide helper utilities: `McpUriTemplateManagerFactory` and `DefaultMcpUriTemplateManager` (`mcp/src/.../util/`). Developers can use these within their handler to match URIs against known templates and extract variables.

    ```java
    // Handler registered via builder.resources(...)
    BiFunction<McpAsyncServerExchange, ReadResourceRequest, Mono<ReadResourceResult>> readHandler =
        (exchange, req) -> Mono.defer(() -> {
            String requestedUri = req.uri();
            // Use provided URI template manager (factory injected or created)
            McpUriTemplateManager userTemplate = uriTemplateFactory.create("users://{userId}/profile");

            if (userTemplate.matches(requestedUri)) {
                Map<String, String> params = userTemplate.extractVariableValues(requestedUri);
                String userId = params.get("userId");
                // ... fetch profile for userId ...
                return Mono.just(new ReadResourceResult(/* ... */));
            }
            // ... check other templates ...
            return Mono.error(new McpError("Resource not found: " + requestedUri));
        });
    ```

**Comparison:** TypeScript and Python offer much more integrated and automatic handling of URI templates and parameter binding in their high-level APIs. C# and Java require manual parsing and matching within the single read handler, though Java provides utility classes to aid this.

### Content Handling: Text, Binary, and MIME Types

MCP distinguishes between text and binary resource content.

*   **Protocol Level:** `TextResourceContents` (has `text` field) vs. `BlobResourceContents` (has `blob` field with base64 data). Both have optional `mimeType`.
*   **TypeScript:** Handler returns `{ contents: [...] }`. If `contents.text` is set, it becomes `TextResourceContents`. If `contents.blob` (expected as base64 string) is set, it becomes `BlobResourceContents`. `mimeType` is set explicitly.
*   **Python `FastMCP`:** Handler return type determines conversion:
    *   `str` -> `TextResourceContents` (`mimeType` defaults to `text/plain` or from decorator).
    *   `bytes` -> `BlobResourceContents` (auto-base64 encoded, `mimeType` defaults to `application/octet-stream` or from decorator).
    *   `dict`, `list`, Pydantic models -> JSON string -> `TextResourceContents` (`mimeType` defaults to `application/json` or from decorator).
*   **C# (Low-Level Handler):** Handler must return `ReadResourceResult` containing a list of `TextResourceContents` or `BlobResourceContents`. Developer manually creates the correct type and performs base64 encoding for blobs. `mimeType` is set on the content objects.
*   **Java (Low-Level Handler):** Handler must return `ReadResourceResult` containing a list of `TextResourceContents` or `BlobResourceContents`. Developer manually creates the correct type and performs base64 encoding for blobs. `mimeType` is set on the content objects.

**Key Point:** For binary data, C# and Java handlers must perform the base64 encoding themselves before creating the `BlobResourceContents` object. Python and TypeScript (if provided raw bytes) handle the encoding implicitly. Specifying the correct `mimeType` is crucial for the client.

### Discovery: `list_resources` and `list_resource_templates`

*   **`list_resources`:** Should return *concrete*, usable resource URIs.
    *   *TS/Python/C#/Java:* Handlers typically return statically defined resources.
    *   *TS/Python:* The `ResourceTemplate` concept *can* include an optional `list` callback (TS) or similar logic (Python could simulate this) to dynamically enumerate concrete URIs matching the template (e.g., list all files in a directory matching `files://*`). The results are merged with static resources.
    *   *C#/Java:* The single `list_resources` handler is responsible for returning *all* listable resources, both static and dynamically generated ones.
*   **`list_resource_templates`:** Should return metadata about the available URI *patterns*.
    *   *TS/Python:* The SDKs automatically expose templates registered via `new ResourceTemplate(...)` (TS) or `@mcp.resource("uri/{template}")` (Python).
    *   *C#/Java:* Requires a dedicated handler (`WithListResourceTemplatesHandler`) to be registered, which manually returns the list of `ResourceTemplate` metadata objects.

**Comparison:** TS and Python have more built-in support for linking dynamic listing logic directly to templates. C# and Java require more manual implementation within the main list handlers.

### Advanced: Argument Completion (TypeScript Focus)

As mentioned in [Blog 9](link-to-post-9), the TypeScript SDK allows defining completion logic directly within the `ResourceTemplate` definition:

```typescript
// TypeScript Resource Template Completion
const categoryCompleter = (partial: string) => ["books", "movies"].filter(c => c.startsWith(partial));

mcpServer.resource(
  "items",
  new ResourceTemplate("items://{category}/{itemId}", {
    list: undefined, // Optional listing callback
    complete: { // Map variable name to completer function
      category: categoryCompleter
      // itemId: (partial, params) => fetchItemIds(params.category, partial) // Can depend on other params
    }
  }),
  async (uri, { category, itemId }) => { /* ... */ }
);
```
The `McpServer` automatically handles the `completion/complete` request for resources defined this way. This feature is not natively built into the other SDKs and would require manual implementation of a `completion/complete` handler.

### Conclusion: Resources - Context is King

Exposing resources effectively is paramount for providing MCP clients and AI models with the necessary context. All four SDKs provide mechanisms for handling both static and dynamic (template-based) resources, but with differing levels of built-in convenience and framework integration.

*   **TypeScript** offers strong integration for URI templates via its `ResourceTemplate` class, including built-in support for argument completion. Dynamic listing is also conceptionalized via template callbacks.
*   **Python's `FastMCP`** provides an ergonomic decorator-based approach where function signatures matching URI template variables enable dynamic resources automatically. It excels at automatic content type conversion.
*   **C#** relies on the developer implementing URI matching and parameter extraction logic within a central read handler, leveraging standard .NET tools like Regex and the flexibility of DI for accessing data sources.
*   **Java** also requires manual handler logic for templates but provides utility classes (`McpUriTemplateManager`) to assist with parsing and matching. Its explicit Specification objects clearly link metadata to handlers.

For advanced use cases involving many dynamic resource patterns or needing argument completion, the TypeScript SDK currently offers the most integrated features. For simpler resources or where developers prefer explicit control within handlers, C# and Java provide the necessary building blocks, especially when leveraging their respective framework integrations and utility classes. Python offers the most concise syntax for common cases. Understanding these nuances allows developers to choose the best approach for managing and exposing contextual data within their chosen ecosystem.