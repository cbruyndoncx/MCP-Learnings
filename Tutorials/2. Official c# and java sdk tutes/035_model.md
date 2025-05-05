Okay, here is a detailed draft for Blog Post 2 in the series, focusing on the schema definitions in the C# and Java MCP SDKs.

---

## Blog 2: Defining the Contract - MCP Schemas in C# (.NET) and Java (JVM)

**Series:** Deep Dive into the Model Context Protocol SDKs (C# & Java)
**Post:** 2 of 10

In [Blog 1](link-to-post-1), we introduced the Model Context Protocol (MCP) and its mission to standardize communication between AI models and applications. We also highlighted the official C# and Java SDKs, designed to bring MCP capabilities into the robust .NET and JVM enterprise ecosystems.

Every communication protocol needs a clearly defined language – a precise structure for messages exchanged between parties. This ensures that both client and server understand what data to expect, what fields are required, and what types those fields should have. Without this contractual clarity, integrations become brittle and prone to errors.

This post dives into the core of this contract within the C# and Java SDKs, exploring how they define the MCP message schemas. We'll compare the approaches taken by:

*   **C# SDK:** Leveraging `System.Text.Json`, C# records/classes (POCOs), attributes, and source generation. (Primarily in `src/ModelContextProtocol/Protocol/Types/`)
*   **Java SDK:** Utilizing the Jackson library, Java records/classes (POJOs), and annotations. (Defined largely within `mcp/src/.../spec/McpSchema.java`)

### The Foundation: JSON-RPC 2.0 Revisited

As mentioned previously, MCP uses JSON-RPC 2.0 as its base framing protocol. Both SDKs must represent these core structures:

*   **Request:** `jsonrpc`, `method`, `params`, `id`.
*   **Response (Success):** `jsonrpc`, `id`, `result`.
*   **Response (Error):** `jsonrpc`, `id`, `error` (with `code`, `message`, `data`).
*   **Notification:** `jsonrpc`, `method`, `params` (no `id`).

Let's see how each SDK models this.

### C# & System.Text.Json: Leveraging Modern .NET Features

The C# SDK embraces modern .NET idioms and the built-in `System.Text.Json` library, enhanced by source generation for performance and AOT compatibility.

**Core JSON-RPC Models:**

Types are typically defined as C# `record` types (for immutability) or `class`es (POCOs). Attributes control JSON serialization behavior.

```csharp
// src/ModelContextProtocol/Protocol/Messages/JsonRpcMessage.cs (Simplified)
using System.Text.Json.Serialization;
using ModelContextProtocol.Utils.Json; // For custom converter

[JsonConverter(typeof(JsonRpcMessageConverter))] // Handles polymorphism
public abstract class JsonRpcMessage
{
    [JsonPropertyName("jsonrpc")]
    public string JsonRpc { get; init; } = "2.0";
    // Note: RelatedTransport is JsonIgnore'd, not part of the schema
}

// src/ModelContextProtocol/Protocol/Messages/JsonRpcRequest.cs (Simplified)
using System.Text.Json.Nodes; // Often uses JsonNode for flexible params/result

public class JsonRpcRequest : JsonRpcMessageWithId // Inherits Id property
{
    [JsonPropertyName("method")]
    public required string Method { get; init; } // 'required' keyword

    [JsonPropertyName("params")]
    public JsonNode? Params { get; init; } // Nullable reference type '?'
}

// src/ModelContextProtocol/Protocol/Messages/JsonRpcErrorDetail.cs (Simplified)
public record JsonRpcErrorDetail
{
    [JsonPropertyName("code")]
    public required int Code { get; init; }

    [JsonPropertyName("message")]
    public required string Message { get; init; }

    [JsonPropertyName("data")]
    public object? Data { get; init; } // Allows any extra data
}
```

**Key `System.Text.Json` / C# Features Used:**

*   **POCOs (Records/Classes):** Standard C# types define the structure. `record` types are often used for their value semantics and conciseness.
*   **`[JsonPropertyName("...")]`**: Maps C# property names (typically PascalCase) to JSON field names (typically camelCase).
*   **`required` Modifier:** Ensures essential properties are present during deserialization and initialization (C# 11+).
*   **Nullability (`?`)**: Clearly indicates optional fields.
*   **`[JsonConverter(typeof(...))]`**: Used on base types (`JsonRpcMessage`, `ResourceContents`) to handle *polymorphic deserialization* – determining the correct concrete type based on JSON properties (e.g., presence of `id`, `method`, `result`, `error`).
*   **`[JsonIgnore]`**: Excludes properties (like `RelatedTransport`) from serialization.
*   **Source Generation (`JsonSerializable`, `JsonSourceGenerationOptions` in `McpJsonUtilities.cs`):** Although not visible directly in the type definition, the SDK uses source generation (`JsonSerializerContext`) to create optimized (de)serialization logic at compile time. This improves performance and is crucial for Native AOT compatibility. The `McpJsonUtilities.DefaultOptions` likely configures the serializer to use this context.
*   **`JsonNode` / `JsonElement`:** Used for flexible `params` and `result` fields where the exact structure varies by method.

**Building MCP Types:**

Specific MCP types inherit or compose these base types:

```csharp
// src/ModelContextProtocol/Protocol/Types/InitializeRequestParams.cs
public class InitializeRequestParams : RequestParams // Base class not shown, likely empty
{
    [JsonPropertyName("protocolVersion")]
    public required string ProtocolVersion { get; init; }

    [JsonPropertyName("capabilities")]
    public ClientCapabilities? Capabilities { get; init; }

    [JsonPropertyName("clientInfo")]
    public required Implementation ClientInfo { get; init; }
}

// src/ModelContextProtocol/Protocol/Types/Tool.cs
public class Tool
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("description")]
    public string? Description { get; set; }

    [JsonPropertyName("inputSchema")]
    public JsonElement InputSchema // Represents the JSON Schema object
    {
        get => _inputSchema;
        set { /* validation logic */ _inputSchema = value; }
    }
    private JsonElement _inputSchema = McpJsonUtilities.DefaultMcpToolSchema;

    // ... Annotations ...
}

// src/ModelContextProtocol/Protocol/Types/ResourceContents.cs (Polymorphism)
[JsonConverter(typeof(Converter))] // Custom converter handles type deduction
public abstract class ResourceContents { /* ... common fields ... */ }

public class TextResourceContents : ResourceContents { /* ... text field ... */ }
public class BlobResourceContents : ResourceContents { /* ... blob field ... */ }
```

The C# approach feels very integrated with the language (nullability, `required`) and the modern .NET serialization library, prioritizing performance and AOT via source generation. Polymorphism is handled via custom `JsonConverter` implementations.

### Java & Jackson: Annotation-Driven Configuration

The Java SDK relies heavily on the ubiquitous [Jackson](https://github.com/FasterXML/jackson) library for JSON processing, using annotations extensively to configure serialization and deserialization. Most MCP types are defined as nested static records or classes within a single large `McpSchema.java` file.

**Core JSON-RPC Models:**

```java
// mcp/src/.../spec/McpSchema.java (Simplified)
import com.fasterxml.jackson.annotation.*;
// ... other imports

public final class McpSchema {

    // Base interface - used with @JsonSubTypes
    public sealed interface JSONRPCMessage permits JSONRPCRequest, JSONRPCNotification, JSONRPCResponse {
        String jsonrpc();
    }

    @JsonInclude(JsonInclude.Include.NON_ABSENT)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record JSONRPCRequest(
            @JsonProperty("jsonrpc") String jsonrpc,
            @JsonProperty("method") String method,
            @JsonProperty("id") Object id, // Often Object or custom Id type needed
            @JsonProperty("params") Object params // Flexible params
    ) implements JSONRPCMessage {}

    @JsonInclude(JsonInclude.Include.NON_ABSENT)
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record JSONRPCResponse(
            @JsonProperty("jsonrpc") String jsonrpc,
            @JsonProperty("id") Object id,
            @JsonProperty("result") Object result, // Flexible result
            @JsonProperty("error") JSONRPCError error // Can be null
    ) implements JSONRPCMessage {

        @JsonInclude(JsonInclude.Include.NON_ABSENT)
        @JsonIgnoreProperties(ignoreUnknown = true)
        public record JSONRPCError(
                @JsonProperty("code") int code,
                @JsonProperty("message") String message,
                @JsonProperty("data") Object data // Flexible extra data
        ) {}
    }
    // ... JSONRPCNotification ...
}
```

**Key Jackson / Java Features Used:**

*   **POJOs (Records/Classes):** Standard Java types define the structure. Nested static `record`s are frequently used for conciseness and immutability.
*   **`@JsonProperty("...")`**: Maps Java field names (camelCase) to JSON field names (often also camelCase, but ensures mapping). Essential as Java doesn't have built-in field name mapping like C#'s source gen or reflection attributes by default for all cases.
*   **`@JsonInclude(JsonInclude.Include.NON_ABSENT)`**: Prevents `null` or empty collection fields from being included in the serialized JSON, matching MCP spec conventions.
*   **`@JsonIgnoreProperties(ignoreUnknown = true)`**: Allows deserialization even if the JSON contains extra, unexpected fields (crucial for MCP's extensibility).
*   **`@JsonTypeInfo` / `@JsonSubTypes`**: Used on base types (`Content`, `ResourceContents`) to handle polymorphism. Jackson deduces the correct subclass based on a type identifier field (like `"type": "text"`).
*   **Standard Java Types:** Uses `String`, `Integer`, `Boolean`, `Double`, `List<>`, `Map<>`. Nullability is handled by standard Java reference types being nullable.
*   **`Object` Type:** Often used for `params` and `result` where the structure is highly variable. Further processing/casting might be needed after initial deserialization.

**Building MCP Types:**

```java
// mcp/src/.../spec/McpSchema.java (Simplified Examples)

// InitializeRequest defined as a nested record
@JsonInclude(JsonInclude.Include.NON_ABSENT)
@JsonIgnoreProperties(ignoreUnknown = true)
public record InitializeRequest(
    @JsonProperty("protocolVersion") String protocolVersion,
    @JsonProperty("capabilities") ClientCapabilities capabilities,
    @JsonProperty("clientInfo") Implementation clientInfo
) implements Request {} // 'Request' is a marker interface

// Tool defined as a nested record
@JsonInclude(JsonInclude.Include.NON_ABSENT)
@JsonIgnoreProperties(ignoreUnknown = true)
public record Tool(
    @JsonProperty("name") String name,
    @JsonProperty("description") String description,
    // Schema is often handled as Map<String, Object> or JsonNode in Jackson
    @JsonProperty("inputSchema") JsonSchema inputSchema
) {}

// ResourceContents using polymorphism annotations
@JsonTypeInfo(use = JsonTypeInfo.Id.DEDUCTION, include = JsonTypeInfo.As.PROPERTY)
@JsonSubTypes({
    @JsonSubTypes.Type(value = TextResourceContents.class, name = "text"),
    @JsonSubTypes.Type(value = BlobResourceContents.class, name = "blob")
})
public sealed interface ResourceContents permits TextResourceContents, BlobResourceContents {
    String uri();
    String mimeType();
}

@JsonInclude(JsonInclude.Include.NON_ABSENT)
@JsonIgnoreProperties(ignoreUnknown = true)
public record TextResourceContents(
    @JsonProperty("uri") String uri,
    @JsonProperty("mimeType") String mimeType,
    @JsonProperty("text") String text
) implements ResourceContents {}

// ... BlobResourceContents ...
```

The Java SDK heavily relies on Jackson's powerful annotation system within standard Java record/class definitions. The use of nested types keeps all protocol definitions within the `McpSchema.java` file, which is convenient but can make the file very large. Polymorphism is handled cleanly using Jackson's built-in annotations.

### Comparison: System.Text.Json (C#) vs. Jackson (Java) for MCP

| Feature         | `System.Text.Json` (C#)              | Jackson (Java)                              | Notes for MCP                                                                                                                               |
| :-------------- | :----------------------------------- | :------------------------------------------ | :------------------------------------------------------------------------------------------------------------------------------------------ |
| **Library**     | Built-in .NET                        | De facto standard Java JSON lib (external dep) | Both are highly capable and widely used.                                                                                                  |
| **Configuration** | Attributes, `JsonSerializerOptions`  | Annotations, `ObjectMapper` modules        | Both use attributes/annotations heavily. C# options often leverage source-gen context; Java uses `ObjectMapper` configuration.              |
| **POCOs/POJOs** | Records / Classes                    | Records / Classes (often nested)            | Similar object mapping approaches. Java SDK heavily uses nested types within `McpSchema.java`.                                               |
| **Polymorphism**| Custom `JsonConverter` needed        | Built-in (`@JsonTypeInfo`, `@JsonSubTypes`) | Jackson has more built-in, annotation-driven support for polymorphic types like `Content` and `ResourceContents`.                             |
| **Null Handling** | C# Nullable Reference Types (`?`)    | Standard Java nullable references           | C# provides more explicit compile-time null safety checks.                                                                                  |
| **Extensibility** | `[JsonExtensionData]` (less used here) | `@JsonIgnoreProperties(ignoreUnknown=true)` | Both handle unexpected fields well. Java's `@JsonIgnoreProperties` is crucial for MCP. C# relies on default behavior or specific settings. |
| **Performance** | High (esp. with Source Generation) | High (mature, optimized)                    | C#'s source generation offers potential advantages, especially for AOT. Jackson is highly optimized through maturity.                       |

Both SDKs successfully map the MCP schema to their respective language's object models using standard, powerful JSON libraries. C# leans on modern language features and source generation for type safety and performance, while Java leverages the extensive annotation-based configuration of Jackson.

### End-User Impact: The Unseen Foundation

While users don't directly interact with these schema definitions, they form the bedrock of a reliable MCP experience:

1.  **Interoperability:** Correctly defined schemas ensure that a C# client can talk to a Java server (or Python/TS servers) and vice-versa, as long as they agree on the protocol version. The data structures match.
2.  **Reduced Errors:** Validation catches malformed messages early, preventing confusing application errors downstream that the user might otherwise encounter.
3.  **Feature Consistency:** When a client requests `listTools`, the structure of the `Tool` objects received will be consistent regardless of the server's implementation language, thanks to the shared schema.
4.  **Enabling Development:** These precise definitions allow SDK developers to build higher-level APIs (like the server builders or client methods) that are intuitive and type-safe, accelerating the development of useful MCP features for end-users.

### Conclusion

Defining the data contract is a fundamental task for any protocol SDK. Both the C# and Java MCP SDKs accomplish this effectively using the standard JSON libraries and idiomatic patterns of their respective platforms – `System.Text.Json` with POCOs and source generation in .NET, and Jackson with POJOs and annotations in Java. These carefully crafted schemas ensure that clients and servers speak the same language, enabling the reliable, cross-platform communication that MCP promises.

With the contract defined, how do we actually *build* servers using these SDKs? In the next post, **Blog 3: Server APIs - Building Blocks**, we'll compare the high-level APIs and patterns (`IMcpServerBuilder` in C# vs. the `McpServer.sync/async` builders in Java) used to configure and launch MCP servers.

---