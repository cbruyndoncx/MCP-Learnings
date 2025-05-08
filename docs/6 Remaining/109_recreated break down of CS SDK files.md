Okay, let's meticulously list the C# SDK files, attempting to order them from least internally dependent to most internally dependent, along with their purpose. This ordering is approximate, as dependencies can be complex, but it follows a general flow from foundational definitions to higher-level abstractions and integrations.

**Level 0: Foundational Utilities & Polyfills (Minimal internal SDK dependencies; rely on .NET BCL)**

1.  `Common/Polyfills/**/*.cs`:
    *   **Files:** Numerous files under `System/`, `System/Collections/`, `System/Diagnostics/`, etc. (e.g., `CollectionExtensions.cs`, `DynamicallyAccessedMembersAttribute.cs`, `StreamExtensions.cs`, `TaskExtensions.cs`, `IsExternalInit.cs`, `RequiredMemberAttribute.cs`, etc.)
    *   **Purpose:** Provide implementations of newer .NET APIs and attributes for older target frameworks (like netstandard2.0 or net472) that the SDK supports. This allows the main SDK code to use modern C# features and APIs consistently across targets. They depend almost exclusively on the base .NET libraries for the specific framework they are polyfilling.
2.  `Common/Utils/Throw.cs`:
    *   **Purpose:** Contains static helper methods (`IfNull`, `IfNullOrWhiteSpace`) for concisely throwing common argument exceptions. Reduces boilerplate code.
    *   **Dependencies:** .NET BCL Exceptions (`ArgumentNullException`, `ArgumentException`).
3.  `Common/Utils/SemaphoreSlimExtensions.cs`:
    *   **Purpose:** Provides the `LockAsync` extension method for `SemaphoreSlim`, offering a convenient `using`-based pattern for asynchronous locking.
    *   **Dependencies:** .NET BCL (`SemaphoreSlim`, `ValueTask`, `IDisposable`).

**Level 1: Core Protocol Constants, Enums, Basic Structures, and Exceptions**

4.  `ModelContextProtocol/McpErrorCode.cs`:
    *   **Purpose:** Defines the `McpErrorCode` enum containing standard JSON-RPC error codes used within MCP.
    *   **Dependencies:** .NET BCL Enum.
5.  `ModelContextProtocol/McpException.cs`:
    *   **Purpose:** Defines the primary custom exception class (`McpException`) used throughout the SDK to represent MCP-specific errors, often wrapping an `McpErrorCode`.
    *   **Dependencies:** .NET BCL `Exception`, `McpErrorCode.cs`.
6.  `ModelContextProtocol/Protocol/Messages/RequestId.cs`:
    *   **Purpose:** Defines the `RequestId` struct to represent the JSON-RPC `id` field, which can be a string or a number. Includes a custom `JsonConverter` to handle serialization/deserialization.
    *   **Dependencies:** .NET BCL, `System.Text.Json`.
7.  `ModelContextProtocol/Protocol/Messages/ProgressToken.cs`:
    *   **Purpose:** Defines the `ProgressToken` struct, similar to `RequestId`, representing the token used for progress notifications. Includes a custom `JsonConverter`.
    *   **Dependencies:** .NET BCL, `System.Text.Json`.
8.  `ModelContextProtocol/Protocol/Messages/NotificationMethods.cs`:
    *   **Purpose:** Defines string constants for standard MCP notification method names (e.g., `"notifications/progress"`).
    *   **Dependencies:** None internal.
9.  `ModelContextProtocol/Protocol/Messages/RequestMethods.cs`:
    *   **Purpose:** Defines string constants for standard MCP request method names (e.g., `"tools/list"`).
    *   **Dependencies:** None internal.
10. `ModelContextProtocol/Protocol/Types/Role.cs`:
    *   **Purpose:** Defines the `Role` enum (`User`, `Assistant`). Uses `CustomizableJsonStringEnumConverter`.
    *   **Dependencies:** `Utils/Json/CustomizableJsonStringEnumConverter.cs`.
11. `ModelContextProtocol/Protocol/Types/LoggingLevel.cs`:
    *   **Purpose:** Defines the `LoggingLevel` enum (Debug, Info, etc.). Uses `CustomizableJsonStringEnumConverter`.
    *   **Dependencies:** `Utils/Json/CustomizableJsonStringEnumConverter.cs`.
12. `ModelContextProtocol/Protocol/Types/ContextInclusion.cs`:
    *   **Purpose:** Defines the `ContextInclusion` enum (None, ThisServer, AllServers). Uses `CustomizableJsonStringEnumConverter`.
    *   **Dependencies:** `Utils/Json/CustomizableJsonStringEnumConverter.cs`.
13. `ModelContextProtocol/Protocol/Types/Implementation.cs`:
    *   **Purpose:** Defines the simple `Implementation` class used to identify clients and servers (`Name`, `Version`).
    *   **Dependencies:** .NET BCL.

**Level 2: JSON-RPC Message Structures & Basic MCP Types**

14. `ModelContextProtocol/Protocol/Messages/JsonRpcMessage.cs`:
    *   **Purpose:** Abstract base class for all JSON-RPC messages (`jsonrpc` property). Contains the crucial `[JsonConverter]` attribute pointing to `JsonRpcMessageConverter`.
    *   **Dependencies:** `Utils/Json/JsonRpcMessageConverter.cs`.
15. `ModelContextProtocol/Protocol/Messages/JsonRpcMessageWithId.cs`:
    *   **Purpose:** Abstract base class for messages that have an ID (Requests, Responses, Errors). Inherits `JsonRpcMessage`.
    *   **Dependencies:** `JsonRpcMessage.cs`, `RequestId.cs`.
16. `ModelContextProtocol/Protocol/Messages/JsonRpcNotification.cs`:
    *   **Purpose:** Represents a JSON-RPC Notification message (`method`, `params`). Inherits `JsonRpcMessage`.
    *   **Dependencies:** `JsonRpcMessage.cs`, `System.Text.Json.Nodes`.
17. `ModelContextProtocol/Protocol/Messages/JsonRpcRequest.cs`:
    *   **Purpose:** Represents a JSON-RPC Request message (`method`, `id`, `params`). Inherits `JsonRpcMessageWithId`.
    *   **Dependencies:** `JsonRpcMessageWithId.cs`, `System.Text.Json.Nodes`.
18. `ModelContextProtocol/Protocol/Messages/JsonRpcErrorDetail.cs`:
    *   **Purpose:** Record defining the structure of the `error` object within an error response (`code`, `message`, `data`).
    *   **Dependencies:** .NET BCL.
19. `ModelContextProtocol/Protocol/Messages/JsonRpcError.cs`:
    *   **Purpose:** Represents a JSON-RPC Error Response message. Inherits `JsonRpcMessageWithId`.
    *   **Dependencies:** `JsonRpcMessageWithId.cs`, `JsonRpcErrorDetail.cs`.
20. `ModelContextProtocol/Protocol/Messages/JsonRpcResponse.cs`:
    *   **Purpose:** Represents a successful JSON-RPC Response message (`result`). Inherits `JsonRpcMessageWithId`.
    *   **Dependencies:** `JsonRpcMessageWithId.cs`, `System.Text.Json.Nodes`.
21. `ModelContextProtocol/Protocol/Types/Annotations.cs`:
    *   **Purpose:** Defines the `Annotations` record used within other primitives (`audience`, `priority`).
    *   **Dependencies:** `Role.cs`.
22. `ModelContextProtocol/Protocol/Types/RequestParamsMetadata.cs`:
    *   **Purpose:** Defines the structure of the optional `_meta` field within request parameters (e.g., `progressToken`).
    *   **Dependencies:** `ProgressToken.cs`.
23. `ModelContextProtocol/Protocol/Types/RequestParams.cs`:
    *   **Purpose:** Abstract base class intended for specific request parameter types (like `InitializeRequestParams`). Includes the optional `Meta` property.
    *   **Dependencies:** `RequestParamsMetadata.cs`.
24. `ModelContextProtocol/Protocol/Messages/PaginatedResult.cs`:
    *   **Purpose:** Base class for response results that support pagination, defining the `NextCursor` property.
    *   **Dependencies:** .NET BCL.
25. `ModelContextProtocol/Protocol/Types/EmptyResult.cs`:
    *   **Purpose:** Represents an empty result for successful operations that return no specific data.
    *   **Dependencies:** .NET BCL.

**Level 3: Complex MCP Payload Types (Primitives, Capabilities, Content)**

26. `ModelContextProtocol/Protocol/Types/Content.cs`:
    *   **Purpose:** Defines the versatile `Content` class used in messages/results, representing text, image, audio, or embedded resources based on its `Type` property.
    *   **Dependencies:** `Annotations.cs`, `Role.cs` (via Annotations), `ResourceContents.cs`.
27. `ModelContextProtocol/Protocol/Types/ResourceContents.cs`:
    *   **Purpose:** Abstract base class for resource content. Defines common fields (`Uri`, `MimeType`) and the custom `JsonConverter` for polymorphism.
    *   **Dependencies:** `Utils/Json/JsonRpcMessageConverter.cs` (Conceptually similar converter needed, maybe defined internally or re-used).
28. `ModelContextProtocol/Protocol/Types/TextResourceContents.cs`:
    *   **Purpose:** Concrete class for text-based resource content (`Text` property). Inherits `ResourceContents`.
    *   **Dependencies:** `ResourceContents.cs`.
29. `ModelContextProtocol/Protocol/Types/BlobResourceContents.cs`:
    *   **Purpose:** Concrete class for binary resource content (`Blob` property as base64 string). Inherits `ResourceContents`.
    *   **Dependencies:** `ResourceContents.cs`.
30. `ModelContextProtocol/Protocol/Types/PromptMessage.cs`:
    *   **Purpose:** Defines the structure of messages within a prompt result (`role`, `content`).
    *   **Dependencies:** `Role.cs`, `Content.cs`, `EmbeddedResource.cs` (defined within).
31. `ModelContextProtocol/Protocol/Types/SamplingMessage.cs`:
    *   **Purpose:** Defines the structure of messages used in sampling requests (`role`, `content`).
    *   **Dependencies:** `Role.cs`, `Content.cs` (but restricted to Text/Image/Audio).
32. `ModelContextProtocol/Protocol/Types/Resource.cs`:
    *   **Purpose:** Defines the metadata structure for a Resource.
    *   **Dependencies:** `Annotations.cs`.
33. `ModelContextProtocol/Protocol/Types/ResourceTemplate.cs`:
    *   **Purpose:** Defines the metadata structure for a Resource Template.
    *   **Dependencies:** `Annotations.cs`.
34. `ModelContextProtocol/Protocol/Types/ToolAnnotations.cs`:
    *   **Purpose:** Defines optional behavioral hints for Tools.
    *   **Dependencies:** .NET BCL.
35. `ModelContextProtocol/Protocol/Types/Tool.cs`:
    *   **Purpose:** Defines the metadata structure for a Tool, including its `InputSchema` as a `JsonElement`.
    *   **Dependencies:** `ToolAnnotations.cs`, `System.Text.Json`.
36. `ModelContextProtocol/Protocol/Types/PromptArgument.cs`:
    *   **Purpose:** Defines the structure for describing arguments accepted by Prompts.
    *   **Dependencies:** .NET BCL.
37. `ModelContextProtocol/Protocol/Types/Prompt.cs`:
    *   **Purpose:** Defines the metadata structure for a Prompt.
    *   **Dependencies:** `PromptArgument.cs`.
38. `ModelContextProtocol/Protocol/Types/Root.cs`:
    *   **Purpose:** Defines the structure for representing a client Root.
    *   **Dependencies:** .NET BCL.
39. `ModelContextProtocol/Protocol/Types/ModelHint.cs`, `ModelPreferences.cs`:
    *   **Purpose:** Define structures related to sampling model preferences.
    *   **Dependencies:** `ModelHint.cs` depends on BCL, `ModelPreferences.cs` depends on `ModelHint.cs`.
40. `ModelContextProtocol/Protocol/Types/Reference.cs`, `Argument.cs`, `Completion.cs`:
    *   **Purpose:** Define structures specific to the argument completion feature (`ref`, `argument`, `completion` result structure).
    *   **Dependencies:** .NET BCL.
41. `ModelContextProtocol/Protocol/Types/*Capability.cs` (`ClientCapabilities.cs`, `ServerCapabilities.cs`, `LoggingCapability.cs`, `PromptsCapability.cs`, `ResourcesCapability.cs`, `ToolsCapability.cs`, `CompletionsCapability.cs`, `RootsCapability.cs`, `SamplingCapability.cs`):
    *   **Purpose:** Define the structures used to declare supported features during initialization. They often contain boolean flags or `[JsonIgnore]`-ed `Func<>` delegates for handlers (set via configuration/DI).
    *   **Dependencies:** Other specific MCP Types (e.g., `McpServerTool`, `McpServerPrompt` for collections, specific `*RequestParams`, `*Result` types for handler signatures). `Server/RequestContext.cs`.

**Level 4: Foundational Interfaces & Shared Logic**

42. `ModelContextProtocol/IMcpEndpoint.cs`:
    *   **Purpose:** Core shared interface defining basic endpoint operations (`SendMessageAsync`, `SendRequestAsync`, `RegisterNotificationHandler`, `DisposeAsync`).
    *   **Dependencies:** `Protocol/Messages/*` (basic JSON-RPC types), `Func<>` delegates.
43. `ModelContextProtocol/Protocol/Transport/ITransport.cs`:
    *   **Purpose:** Interface defining the contract for an active, established communication session (provides `MessageReader`, `SendMessageAsync`, `DisposeAsync`).
    *   **Dependencies:** `System.Threading.Channels`, `Protocol/Messages/JsonRpcMessage.cs`.
44. `ModelContextProtocol/Protocol/Transport/IClientTransport.cs`:
    *   **Purpose:** Interface defining the contract for *creating* a client transport session (`ConnectAsync` returning `ITransport`).
    *   **Dependencies:** `ITransport.cs`.
45. `ModelContextProtocol/Shared/NotificationHandlers.cs`, `ModelContextProtocol/Shared/RequestHandlers.cs`:
    *   **Purpose:** Internal helper classes for managing dictionaries of notification and request handlers, respectively, often keyed by method name string. Include logic for registration and invocation.
    *   **Dependencies:** `Protocol/Messages/*`, `Func<>` delegates.
46. `ModelContextProtocol/Shared/McpSession.cs`:
    *   **Purpose:** **The core internal engine.** Manages a single MCP session over an `ITransport`. Handles the message processing loop (`ProcessMessagesAsync`), request/response correlation (`_pendingRequests`), dispatching messages to registered handlers (`RequestHandlers`, `NotificationHandlers`), cancellation tracking (`_handlingRequests`), and basic error handling.
    *   **Dependencies:** `ITransport.cs`, `NotificationHandlers.cs`, `RequestHandlers.cs`, `Protocol/Messages/*`, `McpException.cs`, `Diagnostics.cs`, logging, `System.Threading.Channels`, `System.Collections.Concurrent`.
47. `ModelContextProtocol/Shared/McpEndpoint.cs`:
    *   **Purpose:** Abstract base class providing common implementation for `IMcpEndpoint`, likely containing the `McpSession` instance and delegating core operations to it. Manages disposal and session lifecycle.
    *   **Dependencies:** `IMcpEndpoint.cs`, `McpSession.cs`, `RequestHandlers.cs`, `NotificationHandlers.cs`, logging.
48. `ModelContextProtocol/Protocol/Transport/TransportBase.cs`:
    *   **Purpose:** Abstract base class providing common boilerplate for `ITransport` implementations (channel management via `_messageChannel`, connection state `IsConnected`, logging helpers).
    *   **Dependencies:** `ITransport.cs`, `JsonRpcMessage.cs`, logging, `System.Threading.Channels`.
49. `ModelContextProtocol/Diagnostics.cs`:
    *   **Purpose:** Internal static class providing helpers for creating and managing OpenTelemetry `Activity`s and `Meter`s specific to MCP operations. Includes context propagation helpers.
    *   **Dependencies:** `System.Diagnostics`, `System.Diagnostics.Metrics`, `Protocol/Messages/*`.
50. `ModelContextProtocol/NopProgress.cs`, `ModelContextProtocol/ProgressNotificationValue.cs`, `ModelContextProtocol/TokenProgress.cs`:
    *   **Purpose:** Support classes for the `IProgress<T>` pattern used for progress reporting. `TokenProgress` specifically links reports to an `IMcpEndpoint` and `ProgressToken`.
    *   **Dependencies:** `IMcpEndpoint.cs`, `Protocol/Messages/ProgressToken.cs`, `Protocol/Messages/ProgressNotification.cs`.

**Level 5: Concrete Transport Implementations**

(These depend on `TransportBase` or other transports, specific I/O APIs, and messages)

51. `ModelContextProtocol/Protocol/Transport/StreamServerTransport.cs`, `ModelContextProtocol/Protocol/Transport/StreamClientSessionTransport.cs`:
    *   **Purpose:** Core implementations for transports based on .NET `Stream` objects (e.g., `TextReader`/`TextWriter`). Handle line-delimited JSON framing. `StreamClientSessionTransport` is used internally by Stdio and Stream clients.
    *   **Dependencies:** `TransportBase.cs`, `ITransport.cs`, .NET Streams, `System.Text.Json`.
52. `ModelContextProtocol/Protocol/Transport/StdioServerTransport.cs`, `ModelContextProtocol/Protocol/Transport/StdioClientTransport.cs`, `ModelContextProtocol/Protocol/Transport/StdioClientSessionTransport.cs`, `ModelContextProtocol/Protocol/Transport/StdioClientTransportOptions.cs`:
    *   **Purpose:** Implement Stdio transport. Client launches process (`System.Diagnostics.Process`, `ProcessHelper`); Server wraps `Console` streams. Use the stream transport bases.
    *   **Dependencies:** `Stream*Transport.cs`, `IClientTransport.cs`, `ProcessHelper.cs`, .NET `Process`, `Console`.
53. `ModelContextProtocol/Protocol/Transport/SseWriter.cs`:
    *   **Purpose:** Helper class to format and write messages as Server-Sent Events to a stream. Manages event IDs for potential resumability.
    *   **Dependencies:** `System.Net.ServerSentEvents`, `JsonRpcMessage.cs`, `System.Text.Json`, `System.Threading.Channels`.
54. `ModelContextProtocol/Protocol/Transport/SseClientSessionTransport.cs`, `ModelContextProtocol/Protocol/Transport/SseClientTransport.cs`, `ModelContextProtocol/Protocol/Transport/SseClientTransportOptions.cs`:
    *   **Purpose:** Implements client-side HTTP+SSE (legacy) *or* Streamable HTTP communication based on `SseClientTransportOptions.UseStreamableHttp`. Uses `HttpClient` and `SseParser`. `SseClientTransport` is the factory; `SseClientSessionTransport` is the active session transport.
    *   **Dependencies:** `TransportBase.cs`, `IClientTransport.cs`, `ITransport.cs`, `HttpClient`, `SseParser`, `StreamableHttpClientSessionTransport.cs` (if `UseStreamableHttp` is true).
55. `ModelContextProtocol/Protocol/Transport/StreamableHttpClientSessionTransport.cs`:
    *   **Purpose:** Specific logic for Streamable HTTP client sessions (part of the `SseClientTransport` when `UseStreamableHttp` is true). Handles POSTing messages and processing SSE/JSON responses from POST, plus managing the optional GET stream.
    *   **Dependencies:** `TransportBase.cs`, `ITransport.cs`, `HttpClient`, `SseParser`.
56. `ModelContextProtocol/Protocol/Transport/StreamableHttpServerTransport.cs`:
    *   **Purpose:** Server-side **core logic** for Streamable HTTP (used by ASP.NET Core integration). Implements `ITransport`. Manages session state (though no session ID itself), handles incoming messages via `OnMessageReceivedAsync`, sends responses/notifications via `SseWriter`, interacts with `EventStore` (interface defined but implementation external) for resumability.
    *   **Dependencies:** `ITransport.cs`, `SseWriter.cs`, `JsonRpcMessage.cs`, `System.IO.Pipelines`, `System.Threading.Channels`. Defines `EventStore`.
57. `ModelContextProtocol/Protocol/Transport/StreamableHttpPostTransport.cs`:
    *   **Purpose:** Internal helper used by `StreamableHttpServerTransport` (likely via ASP.NET Core's `StreamableHttpHandler`) to manage the request/response flow specifically for a single HTTP POST within the Streamable HTTP model, ensuring responses go back on the correct connection.
    *   **Dependencies:** `ITransport.cs`, `SseWriter.cs`, `System.IO.Pipelines`.
58. `ModelContextProtocol/Protocol/Transport/StreamClientTransport.cs`:
    *   **Purpose:** Client transport factory that wraps pre-existing `Stream` objects. Useful for testing or custom scenarios.
    *   **Dependencies:** `IClientTransport.cs`, `StreamClientSessionTransport.cs`.

**Level 6: Core Client/Server Implementations & Abstractions**

59. `ModelContextProtocol/Client/IMcpClient.cs`:
    *   **Purpose:** Public interface for MCP clients. Inherits `IMcpEndpoint`. Adds server info/caps properties.
    *   **Dependencies:** `IMcpEndpoint.cs`, `Protocol/Types/*Capabilities.cs`, `Protocol/Types/Implementation.cs`.
60. `ModelContextProtocol/Server/IMcpServer.cs`:
    *   **Purpose:** Public interface for MCP servers. Inherits `IMcpEndpoint`. Adds client info/caps properties, `ServerOptions`, `Services`, `LoggingLevel`, `RunAsync`.
    *   **Dependencies:** `IMcpEndpoint.cs`, `Protocol/Types/*Capabilities.cs`, `Protocol/Types/Implementation.cs`, `McpServerOptions.cs`.
61. `ModelContextProtocol/Client/McpClientOptions.cs`:
    *   **Purpose:** Defines configuration options for creating an `IMcpClient`.
    *   **Dependencies:** `Protocol/Types/ClientCapabilities.cs`, `Protocol/Types/Implementation.cs`.
62. `ModelContextProtocol/Server/McpServerOptions.cs`:
    *   **Purpose:** Defines configuration options for creating an `IMcpServer`. Holds `ServerInfo`, `Capabilities`, timeouts, etc.
    *   **Dependencies:** `Protocol/Types/ServerCapabilities.cs`, `Protocol/Types/Implementation.cs`.
63. `ModelContextProtocol/Client/McpClient.cs`:
    *   **Purpose:** The concrete implementation of `IMcpClient`. Extends `McpEndpoint`. Contains the logic specific to client initialization and capability management.
    *   **Dependencies:** `IMcpClient.cs`, `Shared/McpEndpoint.cs`, `IClientTransport.cs`, `McpClientOptions.cs`, `Protocol/Types/*`, `Protocol/Messages/*`.
64. `ModelContextProtocol/Server/McpServer.cs`:
    *   **Purpose:** The concrete implementation of `IMcpServer`. Extends `McpEndpoint`. Contains logic specific to server initialization response, managing client capabilities, and provides the infrastructure for registering handlers via `McpServerOptions`.
    *   **Dependencies:** `IMcpServer.cs`, `Shared/McpEndpoint.cs`, `ITransport.cs`, `McpServerOptions.cs`, `Protocol/Types/*`, `Protocol/Messages/*`, `IServiceProvider` (optional).
65. `ModelContextProtocol/Server/RequestContext.cs`:
    *   **Purpose:** Container passed to server handler delegates, providing access to the `IMcpServer`, request `Params`, and potentially scoped `Services`.
    *   **Dependencies:** `IMcpServer.cs`, `IServiceProvider`.
66. `ModelContextProtocol/Server/IMcpServerPrimitive.cs`, `McpServerPrimitiveCollection.cs`:
    *   **Purpose:** Defines a base interface for server-side Tools/Prompts and a thread-safe collection (`ConcurrentDictionary`-based) to store them, including a `Changed` event.
    *   **Dependencies:** .NET BCL Collections.

**Level 7: Factories, Extensions, Primitive Wrappers, Attributes**

67. `ModelContextProtocol/Client/McpClientFactory.cs`:
    *   **Purpose:** Provides the static `CreateAsync` method, the primary way to instantiate and connect an `IMcpClient`. Orchestrates transport connection and initialization.
    *   **Dependencies:** `IMcpClient.cs`, `McpClient.cs`, `IClientTransport.cs`, `McpClientOptions.cs`.
68. `ModelContextProtocol/Server/McpServerFactory.cs`:
    *   **Purpose:** Provides the static `Create` method for instantiating an `IMcpServer`. Primarily used internally by DI extensions but can be used manually.
    *   **Dependencies:** `IMcpServer.cs`, `McpServer.cs`, `ITransport.cs`, `McpServerOptions.cs`.
69. `ModelContextProtocol/AIContentExtensions.cs`:
    *   **Purpose:** Crucial extension methods for converting between MCP `Content`/`PromptMessage` types and `Microsoft.Extensions.AI` types (`AIContent`, `ChatMessage`). Enables integration.
    *   **Dependencies:** `Microsoft.Extensions.AI` (external), `Protocol/Types/*` (Content, PromptMessage, Role).
70. `ModelContextProtocol/McpEndpointExtensions.cs`:
    *   **Purpose:** Provides strongly-typed extension methods (`SendRequestAsync<TParams, TResult>`, `SendNotificationAsync<TParams>`) on `IMcpEndpoint` for easier message sending/receiving without manual JSON handling.
    *   **Dependencies:** `IMcpEndpoint.cs`, `Protocol/Messages/*`, `System.Text.Json`.
71. `ModelContextProtocol/Client/McpClientExtensions.cs`:
    *   **Purpose:** Provides high-level, user-friendly extension methods on `IMcpClient` for common operations (`PingAsync`, `ListToolsAsync`, `CallToolAsync`, `ReadResourceAsync`, `GetPromptAsync`, `SubscribeToResourceAsync`, `SetLoggingLevel`, etc.). These wrap `McpEndpointExtensions.SendRequestAsync`.
    *   **Dependencies:** `IMcpClient.cs`, `McpEndpointExtensions.cs`, `Protocol/Types/*`, `Protocol/Messages/*`, `McpClientTool.cs`, `McpClientPrompt.cs`.
72. `ModelContextProtocol/Server/McpServerExtensions.cs`:
    *   **Purpose:** Provides high-level extension methods on `IMcpServer` for server-initiated actions like (`RequestSamplingAsync`, `AsSamplingChatClient`, `AsClientLoggerProvider`, `RequestRootsAsync`).
    *   **Dependencies:** `IMcpServer.cs`, `McpEndpointExtensions.cs`, `Protocol/Types/*`, `Protocol/Messages/*`, `Microsoft.Extensions.AI`, `Microsoft.Extensions.Logging`.
73. `ModelContextProtocol/Client/McpClientTool.cs`:
    *   **Purpose:** Client-side representation of a discovered server Tool. Inherits `Microsoft.Extensions.AI.AIFunction`, enabling direct use with AI clients. Wraps an `IMcpClient` and `Tool` metadata to implement `InvokeCoreAsync` by calling `client.CallToolAsync`. Includes `WithName`/`WithDescription`/`WithProgress` customization methods.
    *   **Dependencies:** `Microsoft.Extensions.AI`, `IMcpClient.cs`, `Protocol/Types/Tool.cs`, `Protocol/Types/CallToolResponse.cs`, `ProgressNotificationValue.cs`.
74. `ModelContextProtocol/Client/McpClientPrompt.cs`:
    *   **Purpose:** Client-side representation of a discovered server Prompt. Wraps `IMcpClient` and `Prompt` metadata. Provides `GetAsync` method to call `client.GetPromptAsync`.
    *   **Dependencies:** `IMcpClient.cs`, `Protocol/Types/Prompt.cs`, `Protocol/Types/GetPromptResult.cs`.
75. `ModelContextProtocol/Server/McpServerTool.cs`, `ModelContextProtocol/Server/McpServerPrompt.cs`:
    *   **Purpose:** Abstract base classes for server-side Tool/Prompt implementations. Define the `ProtocolTool`/`ProtocolPrompt` metadata property and the core `InvokeAsync`/`GetAsync` execution methods. Provide static `Create` factory methods that typically create `AIFunctionMcpServerTool/Prompt` instances.
    *   **Dependencies:** `IMcpServerPrimitive.cs`, `Protocol/Types/Tool.cs`, `Protocol/Types/Prompt.cs`, `RequestContext.cs`, `AIFunction` (external), reflection APIs.
76. `ModelContextProtocol/Server/AIFunctionMcpServerTool.cs`, `ModelContextProtocol/Server/AIFunctionMcpServerPrompt.cs`:
    *   **Purpose:** Concrete implementations of `McpServerTool`/`McpServerPrompt` that wrap an `AIFunction`. Handle argument binding (including DI/context parameters via `AIFunctionFactoryOptions`), schema generation, method invocation, and result conversion.
    *   **Dependencies:** `McpServerTool/Prompt.cs`, `AIFunction` (external), `RequestContext.cs`, `Protocol/Types/*`, `AIContentExtensions.cs`.
77. `ModelContextProtocol/Server/DelegatingMcpServerTool.cs`, `ModelContextProtocol/Server/DelegatingMcpServerPrompt.cs`:
    *   **Purpose:** Abstract base classes useful for creating decorators or wrappers around existing `McpServerTool`/`McpServerPrompt` instances.
    *   **Dependencies:** `McpServerTool/Prompt.cs`.
78. `ModelContextProtocol/Server/*Attribute.cs` (`McpServerToolAttribute.cs`, `McpServerToolTypeAttribute.cs`, `McpServerPromptAttribute.cs`, `McpServerPromptTypeAttribute.cs`):
    *   **Purpose:** Attributes used by DI extensions (`WithToolsFromAssembly`, etc.) to discover methods and classes that should be registered as MCP Tools or Prompts. Contain metadata like `Name`, `Description`, `ToolAnnotations`.
    *   **Dependencies:** .NET BCL Attributes.
79. `ModelContextProtocol/Server/McpServerToolCreateOptions.cs`, `ModelContextProtocol/Server/McpServerPromptCreateOptions.cs`:
    *   **Purpose:** Classes holding configuration options used by the `McpServerTool/Prompt.Create` factory methods, allowing programmatic customization equivalent to attribute properties.
    *   **Dependencies:** `IServiceProvider`, `JsonSerializerOptions`.

**Level 8: Dependency Injection & Hosting Configuration**

80. `ModelContextProtocol/Configuration/IMcpServerBuilder.cs`:
    *   **Purpose:** Defines the fluent builder interface returned by `AddMcpServer`, exposing the `Services` collection.
    *   **Dependencies:** `Microsoft.Extensions.DependencyInjection`.
81. `ModelContextProtocol/Configuration/DefaultMcpServerBuilder.cs`:
    *   **Purpose:** The default, internal implementation of `IMcpServerBuilder`.
    *   **Dependencies:** `IMcpServerBuilder.cs`, `Microsoft.Extensions.DependencyInjection`.
82. `ModelContextProtocol/Server/McpServerHandlers.cs`:
    *   **Purpose:** A container class, typically configured via DI Options, holding the `Func<>` delegates for low-level request handlers (ListTools, CallTool, ReadResource, etc.).
    *   **Dependencies:** `RequestContext.cs`, specific `*RequestParams` and `*Result` types from `Protocol/Types/`.
83. `ModelContextProtocol/Configuration/McpServerOptionsSetup.cs`:
    *   **Purpose:** An `IConfigureOptions<McpServerOptions>` implementation. Runs during DI container build. It retrieves registered `McpServerTool`s, `McpServerPrompt`s, and `IOptions<McpServerHandlers>` from DI and populates the corresponding collections and handler delegates within the final `McpServerOptions`. This wires up the DI registrations to the server configuration.
    *   **Dependencies:** `Microsoft.Extensions.Options`, `Microsoft.Extensions.DependencyInjection`, `McpServerOptions.cs`, `McpServerHandlers.cs`, `McpServerTool.cs`, `McpServerPrompt.cs`.
84. `ModelContextProtocol/Configuration/McpServerBuilderExtensions.cs`:
    *   **Purpose:** **The primary user-facing API for DI configuration.** Defines extension methods like `AddMcpServer`, `WithTools<T>`, `WithPromptsFromAssembly`, `WithListResourcesHandler`, `WithStdioServerTransport`, `WithHttpTransport`. These methods register services, configure options, and add primitives to the DI container.
    *   **Dependencies:** `IMcpServerBuilder.cs`, `Microsoft.Extensions.DependencyInjection`, `McpServerHandlers.cs`, `McpServerOptions.cs`, `ITransport.cs`, `McpServerTool/Prompt.cs`.
85. `ModelContextProtocol/Hosting/SingleSessionMcpServerHostedService.cs`:
    *   **Purpose:** An `IHostedService` implementation used by `WithStdioServerTransport` and `WithStreamServerTransport`. It retrieves the `IMcpServer` from DI and calls `server.RunAsync()` when the .NET host starts, managing the lifecycle for single-session transports.
    *   **Dependencies:** `Microsoft.Extensions.Hosting`, `IMcpServer.cs`.

**Level 9: ASP.NET Core Integration**

86. `ModelContextProtocol.AspNetCore/*`: These files depend heavily on ASP.NET Core abstractions (`HttpContext`, `IEndpointRouteBuilder`, `RequestDelegate`, `IDuplexPipe`, etc.) as well as the core MCP Server components (`McpServerFactory`, `IMcpServer`, `McpServerOptions`) and transports (`StreamableHttpServerTransport`, `SseResponseStreamTransport`).
    *   `HttpServerTransportOptions.cs`: Defines options specific to ASP.NET Core hosting (`IdleTimeout`, `ConfigureSessionOptions`, `RunSessionHandler`).
    *   `HttpMcpSession.cs`: Internal class managing state for a single HTTP-based session.
    *   `IdleTrackingBackgroundService.cs`: Uses hosting and options to clean up idle sessions.
    *   `StreamableHttpHandler.cs` / `SseHandler.cs`: The core request delegates implementing the transport logic using ASP.NET Core APIs.
    *   `HttpMcpServerBuilderExtensions.cs`: Defines `.WithHttpTransport()` for DI setup.
    *   `McpEndpointRouteBuilderExtensions.cs`: Defines `.MapMcp()` for routing setup.

**Level 10: Samples & Tests**

87. `samples/**/*.cs`: Demonstrate usage of the SDK features. Depend on the core SDK libraries (`ModelContextProtocol`), potentially ASP.NET Core integration (`ModelContextProtocol.AspNetCore`), and external libraries (`Microsoft.Extensions.Hosting`, `Anthropic.SDK`).
88. `tests/**/*.cs`: Verify the correctness and behavior of SDK components. Depend on the specific parts of the SDK being tested, testing frameworks (xUnit), mocking libraries (Moq), and utility helpers (`tests/Common`, `tests/ModelContextProtocol.AspNetCore.Tests/Utils`).

This detailed ordering highlights the layered nature of the SDK, moving from fundamental definitions up through core logic, specific implementations, abstractions, and finally application-level integrations and testing.