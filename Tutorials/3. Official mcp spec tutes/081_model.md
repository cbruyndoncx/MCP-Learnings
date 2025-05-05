Okay, here is a detailed draft for the next advanced blog post (Blog 12), focusing on the Resource primitive across the four MCP SDKs.

---

## Blog 12: Advanced Resource Management - Static Data, URI Templates, and Content Handling in MCP SDKs

**Series:** Deep Dive into the Model Context Protocol SDKs
**Post:** 12 of 10 (Advanced Topics)

Continuing our advanced exploration of the Model Context Protocol (MCP) SDKs, we shift from the *action-oriented* [Tool primitive](link-to-post-11) to the *data-oriented* **Resource** primitive. While Tools allow AI to *act*, Resources allow AI to *know* – providing the crucial contextual data (files, database entries, application state, sensor readings) needed for informed reasoning and generation.

For developers building sophisticated MCP servers, effectively managing and exposing resources, especially dynamic ones, requires a deep understanding of how each SDK handles URI patterns, content types, discovery, and context. This post dissects the Resource primitive across the TypeScript, Python, C#, and Java SDKs, targeting advanced users and researchers. We'll compare:

1.  **Static vs. Dynamic Resources:** Implementation of fixed URIs versus powerful URI Templates (RFC 6570).
2.  **Handler Implementation & Parameter Binding:** How request URIs map to server logic and how template variables are accessed.
3.  **Content Representation:** Handling `TextResourceContents`, `BlobResourceContents`, base64 encoding, and MIME types.
4.  **Resource Discovery:** Implementing `list_resources` and `list_resource_templates`.
5.  **Advanced Features:** Argument completion for URI templates.
6.  **Nuances:** Security considerations, large data handling, and stateful resources.

### The Resource Specification: Data via URI

The [MCP specification](https://modelcontextprotocol.io/specification/draft/server/resources) defines Resources as data addressable by a URI. Key aspects:

*   **Identification:** Unique URIs (e.g., `file:///path/to/doc.txt`, `db://customers/123`, `status://app/main`).
*   **Discovery:** Clients use `resources/list` (for concrete URIs) and `resources/templates/list` (for URI patterns).
*   **Access:** Clients use `resources/read` with a specific URI.
*   **Content:** Servers respond with `ReadResourceResult` containing a list of `ResourceContents` (either `TextResourceContents` or `BlobResourceContents`), each potentially having a `mimeType`.
*   **Control:** Resources are primarily "application-controlled" – the client application often decides when and how to incorporate resource data, though models might request reads via tools.

### Static Resources: Fixed Data Endpoints

The simplest form is exposing data at a non-parameterized URI.

*   **TypeScript (`McpServer.resource()` with string URI):** Register a fixed URI directly, providing a callback that receives the URI.
    ```typescript
    mcpServer.resource("status", "app://status", { mimeType: "application/json" },
      async (uri) => ({ contents: [/* ... */] })
    );
    ```
*   **Python (`@mcp.resource()` with static URI):** Decorate a zero-argument function with the fixed URI.
    ```python
    @mcp.resource("config://defaults", mime_type="application/json")
    def get_defaults() -> dict: # Return dict, SDK converts to JSON TextResourceContents
        return {"rate": 5.0}
    ```
*   **C# (`WithReadResourceHandler`):** The handler delegate receives the request URI string and uses conditional logic (e.g., `if (uri == "app://status")`) to identify and serve the static resource.
    ```csharp
    builder.WithReadResourceHandler(async (ctx, ct) => {
        if (ctx.Params?.Uri == "app://status")
            return new ReadResourceResult { /* ... */ };
        // ... handle other URIs or throw ...
    });
    ```
*   **Java (`ResourceSpecification` + Handler):** Create a `Resource` metadata object with the fixed URI and pass it with a handler `BiFunction` in a `ResourceSpecification` to the `McpServer` builder. The handler might still check the URI if it handles multiple static resources.
    ```java
    Resource statusMeta = new Resource("app://status", "Status", ...);
    SyncResourceSpecification statusSpec = new SyncResourceSpecification(statusMeta,
        (exchange, req) -> new ReadResourceResult(/* ... */)
    );
    McpServer.sync(provider).resources(statusSpec).build();
    ```

**Takeaway:** Exposing static resources is straightforward, though C# and Java require more routing/dispatch logic within the handler compared to the more direct registration in TS and Python's high-level APIs.

### Dynamic Resources: The Power and Peril of URI Templates

Exposing resources based on patterns (e.g., `database://{table}/{id}`, `files://{path*}`) requires parsing the requested URI to extract parameters for the handler logic.

*   **TypeScript (`ResourceTemplate` class):**
    *   **Definition:** Pass a `new ResourceTemplate("template/uri/{var}")` to `McpServer.resource()`. The SDK handles matching.
    *   **Parameter Binding:** **Automatic.** The handler callback `async (uri, params, extra)` receives `params` as an object with keys matching template variables (`{ var: "value" }`).
    *   **Parsing:** Uses an internal RFC 6570 parser (`src/shared/uriTemplate.ts`).

*   **Python (`@mcp.resource()` with template URI):**
    *   **Definition:** Use template syntax (`{var}`) in the decorator's URI string.
    *   **Parameter Binding:** **Automatic.** The decorated function's parameter names *must exactly match* the template variables. Type hints (`param: str`, `id: int`) are used for automatic type coercion during binding.
    *   **Parsing:** Uses regex matching internally based on the function signature.

*   **C# (Manual Handling):**
    *   **Definition:** No built-in template registration at the high level. Templates are conceptual patterns implemented within the single `WithReadResourceHandler`.
    *   **Parameter Binding:** **Manual.** The handler receives the raw URI string. Developer must use `Regex.Match`, string splitting, or other methods to check if the URI matches a known pattern and extract variable values. Type conversion is manual.
    *   **Parsing:** Requires manual implementation or external URI template libraries.

*   **Java (Manual Handling + Helpers):**
    *   **Definition:** Similar to C#, templates are conceptual patterns handled within the `readHandler` `BiFunction`.
    *   **Parameter Binding:** **Manual, but aided.** The SDK provides `McpUriTemplateManager` and `DefaultMcpUriTemplateManager` (`mcp/src/.../util/`) to help. Developers register templates with the manager (`uriTemplateFactory.create("template/{var}")`) and then use it within the handler to match incoming URIs (`userTemplate.matches(uri)`) and extract variables (`userTemplate.extractVariableValues(uri)`). Type conversion is manual.
    *   **Parsing:** Uses the helper utilities provided by the SDK.

**Comparison:** TypeScript and Python provide significantly more convenient, integrated handling of URI templates and parameter binding within their high-level APIs. C# requires full manual implementation. Java requires manual implementation but offers SDK utility classes to simplify the parsing and matching aspects. The manual approaches in C#/Java place a greater burden (and potential for error) on the developer for routing and parameter extraction.

### Content Representation: Text, Blobs, and MIME Types

How the SDKs handle the content returned by resource handlers:

*   **`TextResourceContents` vs. `BlobResourceContents`:** The MCP spec requires the server to return one of these types within the `ReadResourceResult.contents` list.
*   **TypeScript:** The handler callback returns an object like `{ contents: [{ uri, mimeType, text?, blob? }] }`. The presence of `text` or `blob` (expected as base64 string) determines the type sent over the wire.
*   **Python `FastMCP`:** Performs automatic conversion based on the handler's return type: `str` -> `Text`, `bytes` -> `Blob` (auto-base64), `dict`/`list`/`BaseModel` -> JSON string -> `Text`. The `mimeType` is taken from the `@mcp.resource` decorator or defaults (`text/plain`, `application/octet-stream`, `application/json`).
*   **C#:** The `WithReadResourceHandler` delegate must return `ValueTask<ReadResourceResult>`. The developer manually creates `TextResourceContents` or `BlobResourceContents` instances, explicitly setting the `Text` or `Blob` (performing base64 encoding manually for blobs) and the `MimeType`. The SDK includes `ReadResourceContents` helpers for easier creation.
*   **Java:** The `readHandler` `BiFunction` must return `ReadResourceResult` (Sync) or `Mono<ReadResourceResult>` (Async). Similar to C#, the developer manually constructs `Text/BlobResourceContents`, performs base64 encoding, and sets the `MimeType`.

**Comparison:** Python provides the most automation for content conversion and encoding. TS requires constructing the correct result structure but handles encoding if raw bytes were somehow involved earlier (less common). C# and Java require the most manual work: constructing the correct content type objects *and* performing base64 encoding for binary data. Explicitly setting `mimeType` is crucial in all SDKs for correct client interpretation.

### Resource Discovery: Lists and Templates

How clients learn about available resources:

*   **`resources/list` (Concrete URIs):**
    *   *TS/Python:* SDKs automatically list resources registered with static URIs. Can be augmented if a `ResourceTemplate` has a dynamic `list` callback (TS concept) or simulated (Python).
    *   *C#/Java:* The single registered list handler (`WithListResourcesHandler` / `listHandler` spec) is fully responsible for returning *all* listable resources, both static and dynamically generated.
*   **`resources/templates/list` (URI Patterns):**
    *   *TS/Python:* The SDKs automatically list templates registered via `new ResourceTemplate()` / `@mcp.resource("{var}")`.
    *   *C#/Java:* Requires a dedicated handler (`WithListResourceTemplatesHandler` / `listTemplatesHandler` spec) to be registered, manually returning `ResourceTemplate` metadata objects.

**Comparison:** Listing *templates* is automated in TS/Python but manual in C#/Java. Listing *concrete resources* requires more manual aggregation logic in C#/Java if mixing static and dynamic enumeration, whereas TS conceptualizes dynamic listing via the template itself.

### Advanced: Argument Completion for Templates (TS)

The TypeScript SDK uniquely offers built-in support for autocompleting *variables within Resource URI Templates*. This uses the same `Completable` schema wrapper approach seen for Prompts, applied within the `ResourceTemplate` constructor's `complete` option map.

```typescript
// TypeScript Resource Template Completion
new ResourceTemplate("database://{dbName}/{table}", {
  list: undefined,
  complete: {
    dbName: async () => listDatabases(), // Autocomplete dbName
    table: async (partial, params) => listTables(params.dbName, partial) // Autocomplete table based on selected dbName
  }
})
```
This requires manual implementation of a `completion/complete` handler in the other SDKs.

### Nuances for Advanced Users & Researchers

*   **Security is Paramount:** URI Templates, especially those accepting path segments (`files://{path*}`), are highly susceptible to **path traversal** and other injection attacks if the extracted parameters are not rigorously sanitized and validated by the handler *before* being used in file system operations, database queries, or API calls. **Never trust template parameters directly.** Always constrain them (e.g., ensure paths stay within an allowed root directory).
*   **Large Data Strategies:** MCP `read_resource` loads the entire content into memory (potentially base64 encoded) before sending. This is unsuitable for multi-gigabyte files or very large database results. Advanced strategies include:
    1.  **Metadata Resource:** Expose a resource like `large_file://{id}/metadata` that returns size, structure, etc., but not the full content.
    2.  **Chunking Tool:** Provide an MCP *Tool* like `read_file_chunk(uri, offset, length)` that allows clients to read large resources piece by piece.
    3.  **External URI Resource:** Expose a resource whose *content* is simply a URI pointing to the actual data in an accessible location (e.g., an S3 pre-signed URL, a public dataset URL). The MCP client then fetches the data directly from that external URI.
*   **Stateful Resources:** Resource content can depend on the current MCP session (e.g., `session://active_document`). Handlers access session state via the context/exchange objects (using the `sessionId`) potentially interacting with external stores (Redis, DB) as discussed in [Blog 11](link-to-post-11).
*   **Resource vs. Tool Choice:** When should data be a Resource vs. the result of a Tool?
    *   *Resource:* Represents relatively stable context or data that can be identified by a URI. Reading should be cheap and idempotent. Good for file contents, configuration, object state, database *schemas*.
    *   *Tool:* Represents an action, query, or computation. Good for running database *queries*, calling external APIs, performing calculations, modifying state.

### Conclusion: Resources - The Contextual Backbone

Resources are the mechanism for grounding MCP interactions in relevant data. All four SDKs provide ways to expose static and dynamic resources, but differ significantly in their approach to URI templates, parameter binding, and content handling.

*   **TypeScript and Python** offer higher-level abstractions (`ResourceTemplate`, `@mcp.resource("{var}")`) that automate URI template parsing and parameter binding, simplifying dynamic resource implementation. Python further automates content type conversion.
*   **C# and Java** require more manual work within central resource handlers to parse URIs, extract parameters, perform base64 encoding, and construct the appropriate `ResourceContents` types, though Java provides utility classes for template matching. C#'s DI integration aids in accessing data sources within handlers.
*   **Advanced features** like argument completion (TS) and sophisticated listing (TS/Python templates) are less built-in for C#/Java.

Developers working with complex, dynamic resources must pay close attention to URI security (sanitization) and consider strategies beyond simple `read_resource` for handling very large datasets. Choosing the right SDK depends on the complexity of the resources being exposed and the developer's preference for automatic inference versus explicit manual control.

---