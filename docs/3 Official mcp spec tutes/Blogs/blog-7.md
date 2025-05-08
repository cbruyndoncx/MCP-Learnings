---
title: "Blog 7: When the Server Asks - Client Capabilities (Sampling & Roots) Across MCP SDKs"
draft: false
---
## Blog 7: When the Server Asks - Client Capabilities (Sampling & Roots) Across MCP SDKs

**Series:** Deep Dive into the Model Context Protocol SDKs (Advanced Topics)
**Post:** 7 of 12

Thus far in our advanced series on the Model Context Protocol (MCP) SDKs, we've primarily examined features where the *server* provides capabilities (like [Tools](blog-1.md1), [Resources](blog-1.md2), and [Prompts](blog-6.md)) for the client to consume. However, MCP is bidirectional. There are specific capabilities where the roles are reversed: the **client** exposes functionality or information that the **server** can request.

This post delves into the two primary client-side capabilities defined in the [MCP specification](https://modelcontextprotocol.io/specification/draft/client/):

1.  **Sampling (`sampling/createMessage`):** Allowing a server to request an LLM completion *from the client*.
2.  **Roots (`roots/list`, `notifications/roots/list_changed`):** Allowing a server to discover relevant filesystem entry points defined by the client/host application.

We'll analyze how these capabilities are declared, implemented, and handled across the TypeScript, Python, C#, and Java SDKs, focusing on the nuances relevant to advanced developers and researchers.

### The Inversion of Control: Why Client Capabilities?

These features represent an inversion of the typical client-server relationship:

*   **Sampling:** Enables "agentic" servers. A server handling a complex task might need LLM reasoning to proceed but may not have direct LLM access itself (due to cost, security, or architecture). It can delegate the LLM call back to the client (which likely *does* have configured LLM access), potentially incorporating context gathered *by the server*. This also keeps user control central, as the client application (Host) typically intermediates the sampling request for user approval.
*   **Roots:** Allows servers (especially those interacting with local filesystems, like linters, indexers, or build tools) to understand the user's relevant working directories or project scopes without needing hardcoded paths or complex configuration on the server side. The *client/host application* defines the relevant scope.

### Declaring Client Capabilities

Like servers, clients declare their supported capabilities during the [initialization handshake](blog-3.md).

*   **Specification (`ClientCapabilities`):**
    ```json
    {
      "capabilities": {
        "sampling": {}, // Presence indicates support
        "roots": {
          "listChanged": true // Optional: Client will notify on changes
        },
        "experimental": { /* ... */ }
      }
    }
    ```
*   **TypeScript (`new Client(..., options)`):** Capabilities passed in the `options` object during client construction.
    ```typescript
    const client = new Client(clientInfo, {
      capabilities: {
        sampling: { /* Potentially config, but just presence needed */ },
        roots: { listChanged: true }
      }
    });
    ```
*   **Python (`McpClient.async/sync(...).capabilities(...)`):** Set via the builder pattern. Specific handlers are passed separately.
    ```python
    client = McpClient.async(transport)
                .capabilities(ClientCapabilities.builder()
                    .sampling()
                    .roots(list_changed=True)
                    .build())
                # .sampling(sampling_callback) # Handler passed separately
                # .list_roots(list_roots_callback)
                # ...
                .build()
    ```
*   **C# (`McpClientOptions`):** Set via the `Capabilities` property on `McpClientOptions`, which is passed to `McpClientFactory.CreateAsync`. Handlers are properties within the capability objects (`SamplingCapability.SamplingHandler`, `RootsCapability.RootsHandler`).
    ```csharp
    var options = new McpClientOptions {
        Capabilities = new() {
            Sampling = new() { SamplingHandler = MySamplingHandlerAsync },
            Roots = new() { ListChanged = true, RootsHandler = MyRootsHandlerAsync }
        }
        // ... other options
    };
    IMcpClient client = await McpClientFactory.CreateAsync(transport, options);
    ```
*   **Java (`McpClient.async/sync(...).capabilities(...)`):** Similar to Python, capabilities are enabled via the builder, and handlers are passed via separate builder methods (`.sampling(handler)`, `.listRoots(handler)`).
    ```java
    McpAsyncClient client = McpClient.async(transport)
        .capabilities(ClientCapabilities.builder()
            .sampling()
            .roots(true) // enables roots with listChanged
            .build())
        .sampling(mySamplingHandler) // Pass handler function
        .listRoots(myListRootsHandler)
        .build();
    ```

### Handling Server Requests: Implementing Client Logic

When a server sends a `sampling/createMessage` or `roots/list` request, the client SDK needs to route it to the appropriate user-defined logic.

**1. Sampling (`sampling/createMessage`):**

*   **Input:** Server sends `CreateMessageRequestParams` (messages, modelPreferences, systemPrompt, maxTokens, etc.).
*   **Client Logic:** The registered handler receives these parameters. It *should*:
    *   Present the request to the user for approval/modification (crucial security step).
    *   Select an appropriate LLM based on `modelPreferences` and available client models.
    *   Potentially inject context if `includeContext` was requested (implementation specific to the host app).
    *   Call the chosen LLM API.
    *   Present the LLM's response to the user for approval/modification.
    *   Construct and return the `CreateMessageResult` (role, content, model, stopReason).
*   **SDK Handling:**
    *   *TS:* Handler registered via `client.setRequestHandler(CreateMessageRequestSchema, handler)`. Handler receives parsed request and `RequestHandlerExtra`.
    *   *Python:* Handler (`sampling_callback`) passed to `ClientSession` constructor. Receives `RequestContext` and parsed `CreateMessageRequestParams`. Returns `CreateMessageResult` or `ErrorData`.
    *   *C#:* Handler (`SamplingHandler`) set on `SamplingCapability` in `McpClientOptions`. Is a `Func<CreateMessageRequestParams?, IProgress<...>, CancellationToken, ValueTask<CreateMessageResult>>`. Progress reporting is integrated.
    *   *Java:* Handler (`Function<CreateMessageRequest, Mono<CreateMessageResult>>` or sync equivalent) passed to builder via `.sampling(handler)`. Receives parsed `CreateMessageRequest`.
*   **Key Nuance:** C#'s `CreateSamplingHandler` extension method provides a convenient way to wrap any `IChatClient` from `Microsoft.Extensions.AI` into the required handler signature, automatically handling parameter conversion and progress reporting. Other SDKs require more manual implementation of the LLM call and result mapping.

**2. Roots (`roots/list` / `notifications/roots/list_changed`):**

*   **Input (`roots/list`):** Server sends the parameter-less request.
*   **Client Logic (`roots/list` Handler):** The registered handler determines the relevant root URIs (e.g., current project folders, open workspace). It constructs and returns a `ListRootsResult` containing `Root` objects (`uri`, `name`). URIs **MUST** be `file://` URIs.
*   **Client Logic (`roots/list_changed` Notification):** When the relevant roots change (user opens/closes folder, switches projects), the client application logic detects this. If the client declared `roots.listChanged=true`, it *sends* the `notifications/roots/list_changed` notification to the server.
*   **SDK Handling:**
    *   *TS:* `roots/list` handler registered via `client.setRequestHandler(ListRootsRequestSchema, handler)`. `roots/list_changed` sent via `client.sendRootsListChanged()`.
    *   *Python:* `list_roots_callback` passed to `ClientSession` constructor. `roots/list_changed` sent via `session.send_roots_list_changed()`.
    *   *C#:* `RootsHandler` set on `RootsCapability` in `McpClientOptions`. `roots/list_changed` sent via `client.SendNotificationAsync(NotificationMethods.RootsUpdatedNotification, ...)`.
    *   *Java:* `listRoots` handler passed to builder via `.listRoots(handler)`. `roots/list_changed` sent via `client.rootsListChangedNotification()`.

### Advanced Considerations & Comparison

*   **Security & User Control (Sampling):** This is paramount. The *client/host application* is the gatekeeper. SDKs provide the mechanism for the server *request*, but the client *must* implement the human-in-the-loop validation before calling the LLM and before returning the response. Failing to do so creates significant security risks.
*   **Context Injection (Sampling):** The spec allows servers to request context (`includeContext`). How this context is gathered and injected into the LLM prompt is entirely up to the client/host application implementation. The SDKs don't provide built-in mechanisms for this automatic context gathering.
*   **Model Mapping (Sampling):** Clients need logic to interpret `ModelPreferences` (hints, priorities) and map them to locally available LLMs or APIs (OpenAI, Anthropic, Gemini, local models via Ollama, etc.). This mapping logic resides outside the core SDK handlers. C#'s `Microsoft.Extensions.AI` integration might simplify using different backend providers.
*   **Roots Implementation:** Defining "relevant" roots is application-specific. An IDE might use open workspace folders. A file manager might use the currently viewed directory. The logic lives within the client application, exposed via the handler.
*   **Error Handling:** Client handlers for `sampling/createMessage` and `roots/list` should return appropriate JSON-RPC errors if they fail (e.g., user rejects sampling, invalid roots, internal error).
*   **Sync vs. Async (Java):** For sampling, the `Async` API is almost always preferred due to the inherent latency of LLM calls. For `roots/list`, `Sync` might be acceptable if root discovery is fast, but `Async` is generally safer.

### Conclusion: Empowering Servers Through Client Capabilities

Sampling and Roots invert the typical MCP flow, empowering servers by allowing them to leverage client-side LLM access and filesystem context awareness.

*   **Sampling** is the key to enabling complex, server-driven agentic workflows where the server might orchestrate tasks but delegates the core "thinking" (LLM calls) back to the client, keeping API keys and user control localized.
*   **Roots** provide essential grounding for servers operating on local filesystems, ensuring they work within user-defined boundaries.

All four SDKs provide the necessary mechanisms to declare support for these capabilities and register handlers to respond to server requests. C# stands out with its convenient `CreateSamplingHandler` extension for integrating with `IChatClient`. Python and Java offer clear separation via dedicated builder methods or constructor arguments for callbacks. TypeScript uses its consistent `setRequestHandler` pattern.

Implementing these client-side capabilities, especially Sampling with its critical human-in-the-loop requirements, requires careful design by the client application developer. However, when implemented correctly, they unlock powerful new interaction patterns within the MCP ecosystem.

With this exploration of client-side capabilities, we've covered the major functional aspects of the SDKs. Our final post will synthesize the entire series, offering concluding thoughts on the developer experience, use cases, and future directions for MCP across all four platforms.

---
