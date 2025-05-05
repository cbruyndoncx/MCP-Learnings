Okay, here is a detailed draft for Blog Post 2 in the advanced series, focusing on the JSON-RPC core and base MCP types across the SDKs, referencing the specification repository.

---

## Blog 2: The Core Language - JSON-RPC Framing and MCP Base Types Across SDKs

**Series:** Deep Dive into the Model Context Protocol SDKs
**Post:** 2 of 12 (Advanced Topics)

In [Blog 1](link-to-post-1), we established the [`modelcontextprotocol/modelcontextprotocol`](https://github.com/modelcontextprotocol/modelcontextprotocol) repository as the definitive blueprint for the Model Context Protocol (MCP). Now, we peel back the first layer of that blueprint: the fundamental message structure based on **JSON-RPC 2.0** and the core MCP base types that build upon it.

Understanding how each SDK (TypeScript, Python, C#, Java) models these foundational elements is crucial, as it dictates how all subsequent MCP requests, responses, and notifications are structured, serialized, validated, and processed. We'll compare the implementation choices using Zod, Pydantic, `System.Text.Json`, and Jackson, referencing the authoritative definitions in the [specification schema](https://github.com/modelcontextprotocol/specification/tree/main/schema).

### JSON-RPC 2.0: The Chosen Wire Format

MCP leverages the simplicity and widespread support of JSON-RPC 2.0 for its message structure. This choice provides:

*   **Text-Based Format:** Human-readable (JSON) and easily parseable.
*   **Clear Message Types:** Distinguishes between Requests (expecting responses), Responses (results/errors), and Notifications (one-way).
*   **Request Correlation:** Uses an `id` field (string or number) to match responses back to requests, essential for asynchronous communication.
*   **Standard Error Structure:** Defines a consistent way (`error` object with `code`, `message`, `data`) to report failures.

The specification ([basic section](https://modelcontextprotocol.io/specification/draft/basic/)) mandates adherence to JSON-RPC 2.0, with a few MCP-specific constraints (e.g., request `id` cannot be `null`). The `draft` spec notably *removes* support for JSON-RPC batching, simplifying implementations.

### Modeling the Core Structures: SDK Approaches

Let's examine how each SDK defines the fundamental JSON-RPC message types and related base MCP types (`Request`, `Notification`, `Result`, `Params`).

**1. TypeScript (`src/types.ts`) - Zod Schemas & Interfaces**

*   **Approach:** Uses Zod schemas for validation and derives TypeScript interfaces using `z.infer`. Defines constants for versions and error codes.
*   **Core Types:**
    *   `JSONRPC_VERSION = "2.0"` (Constant)
    *   `RequestIdSchema = z.union([z.string(), z.number().int()])` -> `type RequestId = string | number`
    *   `RequestSchema` (base with `method`, optional `params`): `z.object({...})`
    *   `JSONRPCRequestSchema`: Merges `RequestSchema` with `jsonrpc` literal and `id`, marked `.strict()` at the top level.
    *   `NotificationSchema` / `JSONRPCNotificationSchema`: Similar structure, no `id`.
    *   `ResultSchema`: Base for results, allows `_meta`, marked `.passthrough()`.
    *   `JSONRPCResponseSchema`: Contains `id`, `jsonrpc`, and `result` (linking to `ResultSchema`).
    *   `JSONRPCErrorSchema`: Contains `id`, `jsonrpc`, and nested `error` object schema.
    *   `JSONRPCMessageSchema`: A `z.union` of all possible top-level message schemas (Request, Notification, Response, Error). *(Note: The draft spec removed batching, simplifying this)*.
    *   `BaseRequestParamsSchema` / `BaseNotificationParamsSchema`: Defines the optional `_meta` field, marked `.passthrough()`.
*   **Strengths:** Clear separation of schema definition (Zod) and static type (TS interface). Compile-time validation of schema usage. Fluent API for building complex types compositionally. `.strict()` enforces exact top-level structure while `.passthrough()` allows extensibility in `params`/`result`.

**2. Python (`src/mcp/types.py`) - Pydantic Models**

*   **Approach:** Uses Pydantic `BaseModel` subclasses, leveraging Python type hints. Requires explicit `ConfigDict(extra="allow")` on nearly every model due to MCP's flexible `params`/`result`/`_meta`.
*   **Core Types:**
    *   `JSONRPC_VERSION: Literal["2.0"] = "2.0"`
    *   `RequestId = str | int` (Standard Python union type)
    *   `Request` (Generic `BaseModel`): Defines `method: MethodT`, `params: RequestParamsT`. Includes `model_config = ConfigDict(extra="allow")`.
    *   `JSONRPCRequest` (Inherits `Request`): Adds `jsonrpc: Literal[JSONRPC_VERSION]`, `id: RequestId`.
    *   `Notification` / `JSONRPCNotification`: Similar structure, no `id`.
    *   `Result` (`BaseModel`): Defines optional `meta: dict[str, Any] | None = Field(alias="_meta", ...)`. `model_config = ConfigDict(extra="allow")`.
    *   `JSONRPCResponse` (`BaseModel`): Contains `id`, `jsonrpc`, `result: dict[str, Any]`.
    *   `JSONRPCError` (`BaseModel`): Contains `id`, `jsonrpc`, `error: ErrorData`.
    *   `JSONRPCMessage` (`RootModel[Union[...]]`): Pydantic's way to handle top-level discriminated unions based on message structure.
    *   `RequestParams` / `NotificationParams` (Base Models): Define optional `meta: Meta | None = Field(alias="_meta", ...)` with its own `Meta` BaseModel.
*   **Strengths:** Uses native Python type hints and classes. Pydantic provides robust runtime validation. `RootModel` handles the top-level message discrimination. Explicit `extra="allow"` clearly signals where extensibility is permitted.

**3. C# (`src/ModelContextProtocol/Protocol/Messages/`) - POCOs & System.Text.Json**

*   **Approach:** Defines abstract base classes (`JsonRpcMessage`, `JsonRpcMessageWithId`) and concrete record/class types for each message. Uses `[JsonPropertyName]` for mapping and a custom `[JsonConverter(typeof(JsonRpcMessageConverter))]` on the base class for polymorphism. Relies on `System.Text.Json` (often with source generation via `JsonContext`).
*   **Core Types:**
    *   `JsonRpcMessage` (Abstract class): Defines `JsonRpc { get; init; } = "2.0"`. Has `[JsonConverter]`.
    *   `JsonRpcMessageWithId` (Abstract class, inherits `JsonRpcMessage`): Adds `Id { get; init; }`.
    *   `JsonRpcRequest` (Class, inherits `JsonRpcMessageWithId`): Adds `Method`, `Params` (often `JsonNode?`).
    *   `JsonRpcNotification` (Class, inherits `JsonRpcMessage`): Adds `Method`, `Params` (`JsonNode?`).
    *   `JsonRpcResponse` (Class, inherits `JsonRpcMessageWithId`): Adds `Result` (`JsonNode?`).
    *   `JsonRpcError` (Class, inherits `JsonRpcMessageWithId`): Adds `Error` (linking to `JsonRpcErrorDetail` record).
    *   `JsonRpcErrorDetail` (Record): Defines `Code`, `Message`, `Data` (`object?`).
    *   `RequestId` / `ProgressToken`: Structs wrapping `object?` with custom `JsonConverter` to handle string/number duality.
    *   *(Note: Base `RequestParams`/`Result` with `_meta` aren't strictly defined as separate base *types* but handled within specific message parameter/result types where needed).*
*   **Strengths:** Idiomatic C# using classes/records. `required` modifier enforces necessary fields. `System.Text.Json` is performant, especially with source generation (`JsonContext` defined in `Utils/Json/McpJsonUtilities.cs`). Custom converters provide flexibility (polymorphism, RequestId).

**4. Java (`mcp/src/.../spec/McpSchema.java`) - POJOs & Jackson**

*   **Approach:** Defines most types as nested static `record`s or `sealed interface`s within a single `McpSchema` class. Heavy reliance on Jackson annotations (`@JsonProperty`, `@JsonInclude`, `@JsonIgnoreProperties`, `@JsonTypeInfo`, `@JsonSubTypes`).
*   **Core Types:**
    *   `JSONRPCMessage` (Sealed Interface): Base marker.
    *   `JSONRPCRequest` (Record, implements `JSONRPCMessage`): `jsonrpc`, `method`, `id` (`Object`), `params` (`Object`). Annotations `@JsonInclude(Include.NON_ABSENT)`, `@JsonIgnoreProperties(ignoreUnknown = true)`.
    *   `JSONRPCNotification` (Record, implements `JSONRPCMessage`): Similar, no `id`.
    *   `JSONRPCResponse` (Record, implements `JSONRPCMessage`): `jsonrpc`, `id` (`Object`), `result` (`Object`), `error` (`JSONRPCError`).
    *   `JSONRPCResponse.JSONRPCError` (Nested Record): `code`, `message`, `data` (`Object`).
    *   *(Note: Java SDK also defines base `Request`, `Notification`, `Result` interfaces, often used as markers or for generic constraints, but the concrete types usually define fields directly).*
    *   `RequestId` / `ProgressToken`: Often represented directly as `Object` in records, requiring runtime checks or careful casting after deserialization, although custom serializers/deserializers could be used.
*   **Strengths:** Uses standard Java records/interfaces. Jackson is powerful and highly configurable via annotations. `@JsonIgnoreProperties(ignoreUnknown = true)` is essential for MCP's forward compatibility. `@JsonSubTypes` handles polymorphism well.

### Comparing the Foundations

*   **Polymorphism (Top-Level Message):**
    *   TS/Python: Handled by schema union (`z.union` / `RootModel`).
    *   C#: Custom `JsonRpcMessageConverter`.
    *   Java: Sealed interface `JSONRPCMessage` likely works with Jackson's subtype deduction or a custom deserializer.
*   **Extensibility (`params`/`result`/`_meta`):**
    *   TS: `.passthrough()` on nested Zod objects.
    *   Python: `ConfigDict(extra="allow")` explicitly on models.
    *   C#: Default `System.Text.Json` behavior often allows extra fields; can use `[JsonExtensionData]` for explicit capture if needed.
    *   Java: `@JsonIgnoreProperties(ignoreUnknown = true)` is the key annotation.
*   **Optionality/Nullability:**
    *   TS: Zod `.optional()`.
    *   Python: Standard `| None` type hint.
    *   C#: Nullable reference types (`?`).
    *   Java: Standard reference types are nullable. Jackson's `@JsonInclude(Include.NON_ABSENT)` controls serialization.
*   **String/Number Unions (`RequestId`, `ProgressToken`):**
    *   TS/Python: Native language union types + schema definitions.
    *   C#: Custom struct + `JsonConverter`.
    *   Java: Often uses base `Object`, requiring runtime type checking or casting.
*   **Schema Definition Location:**
    *   TS/Python/C#: Types generally defined in dedicated files within logical namespaces/modules.
    *   Java: Concentrated within nested types inside `McpSchema.java`.

### Nuances for Advanced Users

*   **Strictness vs. Extensibility:** MCP requires extensibility in fields like `params`, `result`, `_meta`, and content blocks. All SDKs achieve this, but the mechanism differs (Zod `.passthrough`, Pydantic `extra='allow'`, C# default behavior / `JsonExtensionData`, Jackson `@JsonIgnoreProperties`). Understanding *where* strictness *is* applied (e.g., top-level JSON-RPC fields in TS Zod's `.strict()`) versus where extensibility is allowed is vital.
*   **Flexible Payloads (`params`/`result`):** Handling variable `params` and `result` structures poses a challenge. TS/Python often use generic `unknown`/`Any`/`Dict`, requiring further validation in handlers. C# uses `JsonNode?`/`JsonElement?`, allowing structured access but still needing type-specific deserialization. Java often uses `Object`, necessitating runtime casting or deserialization within handlers. Type safety for specific request/response pairs is typically enforced at the handler registration level (e.g., C#'s `RequestHandlers.Set` or TS's `setRequestHandler` taking specific schemas).
*   **Performance:** C#'s source-generated `System.Text.Json` context likely offers the best raw serialization/deserialization performance and minimal allocation, especially relevant for high-throughput servers or AOT compilation. Jackson (Java) is highly optimized. Zod and Pydantic add a validation layer which, while essential, introduces some overhead compared to purely generated serializers.

### Conclusion

The foundation of MCP communication rests on JSON-RPC 2.0, and each SDK meticulously models these core message structures using idiomatic tools from its ecosystem. TypeScript leverages Zod's explicit schemas and type inference. Python uses Pydantic's type-hint-driven models. C# employs standard POCOs/records with `System.Text.Json` attributes and source generation. Java relies heavily on Jackson annotations and nested types.

While the end result is interoperable JSON, the internal representations and the developer experience of defining and validating these base types differ significantly. Understanding these foundational choices is key to appreciating the subsequent design decisions made in the higher-level server and client APIs, which we will continue to explore in the next posts, starting with **Blog 3: High-Level Server APIs**.

---