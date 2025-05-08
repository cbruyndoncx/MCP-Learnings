Okay, let's break down the `modelcontextprotocol-typescript-sdk` project based on the provided file structure and content.

**Project Overview:**

This repository contains the official TypeScript SDK for the Model Context Protocol (MCP). It provides the necessary tools and abstractions for developers to build both MCP clients and MCP servers in a TypeScript environment. The SDK aims to simplify the implementation of the MCP specification by handling protocol details, transport mechanisms, and core concepts like resources, tools, and prompts. It's authored by Anthropic and licensed under MIT.

**Core Concepts & Purpose:**

*   **MCP Implementation:** The primary goal is to provide a robust and easy-to-use implementation of the MCP specification.
*   **Client/Server Separation:** The SDK clearly separates client-side (`src/client`) and server-side (`src/server`) concerns.
*   **Transport Abstraction:** It defines a `Transport` interface (`src/shared/transport.ts`) and provides concrete implementations for common communication methods like `stdio` and `Streamable HTTP`. An older `SSE` transport is included for backwards compatibility, and a `WebSocket` transport exists for the client. `InMemoryTransport` is provided for testing.
*   **Protocol Handling:** A core `Protocol` class (`src/shared/protocol.ts`) handles the JSON-RPC framing, request/response mapping, notifications, timeouts, and cancellation logic, serving as the base for both `Client` and `Server`.
*   **High-Level Abstractions:** The `McpServer` class (`src/server/mcp.ts`) offers a simplified API on top of the base `Server` class (`src/server/index.ts`) for defining resources, tools, and prompts declaratively.
*   **Schema Definition:** Uses `zod` extensively (`src/types.ts`) to define and validate the MCP message structures, ensuring type safety and protocol compliance.
*   **OAuth Integration:** Provides significant support for OAuth 2.1, including client-side helper functions (`src/client/auth.ts`) and a comprehensive server-side implementation (`src/server/auth/`) with handlers, middleware, and even a proxy provider.
*   **Resumability & State Management:** The `StreamableHTTPServerTransport` supports session management and resumability through an `EventStore` interface (example in `src/examples/shared/inMemoryEventStore.ts`).
*   **Dynamic Capabilities:** Supports adding, removing, enabling, disabling, and updating resources, tools, and prompts *after* the server has connected, automatically notifying clients of changes.

**Key Features & Implementation Details:**

1.  **Client (`src/client`):**
    *   `Client` class provides high-level methods (`listTools`, `callTool`, `readResource`, etc.).
    *   Transport implementations: `StdioClientTransport`, `SSEClientTransport` (deprecated), `StreamableHTTPClientTransport`, `WebSocketClientTransport`.
    *   OAuth client utilities for handling authorization flows.
    *   Capability negotiation during initialization.

2.  **Server (`src/server`):**
    *   `Server` class (low-level) allows direct request/notification handler registration.
    *   `McpServer` class (high-level) simplifies defining tools, resources, and prompts using `.tool()`, `.resource()`, `.prompt()`.
    *   Transport implementations: `StdioServerTransport`, `SSEServerTransport` (deprecated), `StreamableHTTPServerTransport`.
    *   Comprehensive OAuth server implementation (`src/server/auth`):
        *   Router (`mcpAuthRouter`) for standard OAuth endpoints (.well-known, authorize, token, register, revoke).
        *   Handlers for each endpoint.
        *   Middleware for client authentication (`authenticateClient`) and bearer token validation (`requireBearerAuth`).
        *   `ProxyOAuthServerProvider` to delegate authentication to an external provider.
    *   `Completable` (`src/server/completable.ts`): A Zod wrapper to add autocompletion logic to schemas, used for prompt/resource arguments.

3.  **Shared (`src/shared`):**
    *   `protocol.ts`: Core logic for message handling, request timeouts, cancellation, progress.
    *   `types.ts`: Central Zod schemas defining the entire MCP message set and types. Includes protocol version constants.
    *   `transport.ts`: The abstract `Transport` interface.
    *   `auth.ts`: Shared OAuth schemas (metadata, tokens, client info).
    *   `uriTemplate.ts`: RFC 6570 URI Template implementation, crucial for dynamic resources.
    *   `stdio.ts`: Shared logic for stdio message framing.

4.  **Transports:**
    *   **Streamable HTTP:** The modern, recommended transport. Supports stateful (session ID) and stateless modes, as well as resumability via an `EventStore`. Handles GET (SSE stream), POST (messages), and DELETE (session termination).
    *   **Stdio:** For command-line integration. Uses `cross-spawn`.
    *   **SSE (Deprecated):** HTTP+SSE transport from older protocol versions, maintained for backwards compatibility. Uses separate GET (/sse) and POST (/messages) endpoints.
    *   **WebSocket (Client-only):** A client transport using WebSockets.
    *   **InMemory:** For testing client/server interaction within the same process.

5.  **Documentation & Examples:**
    *   `README.md`: Comprehensive overview, quick start, core concepts, transport setup, examples, and advanced usage patterns (dynamic servers, OAuth proxy, backwards compatibility).
    *   `src/examples`: Contains more detailed client and server examples, including different transport configurations (stateless, JSON response mode, backwards compatible) and parallel client scenarios. The examples README provides valuable context on multi-node deployment patterns.

6.  **Testing & Tooling:**
    *   Uses Jest and `ts-jest` for testing.
    *   Unit tests are co-located with source files (`*.test.ts`).
    *   Integration tests (`src/integration-tests`) cover aspects like process cleanup and state management.
    *   ESLint for linting.
    *   TypeScript for static typing.
    *   GitHub Actions (`.github/workflows/main.yml`) for CI (build, lint, test) and CD (publishing to npm on release).

**Strengths:**

*   **Comprehensive:** Covers both client and server implementations thoroughly.
*   **Well-Structured:** Clear separation of concerns (client/server/shared/transport).
*   **Modern TypeScript:** Uses ES Modules, Zod for schemas, standard tooling.
*   **Feature-Rich:** Includes advanced features like dynamic capabilities, OAuth proxying, resumability, autocompletion, and backwards compatibility.
*   **Good Documentation:** The main README is detailed and covers many use cases. The examples README adds context on deployment.
*   **Extensible:** The `Protocol` base class and `Transport` interface allow for customization.
*   **Testing:** Includes unit and integration tests.

**Potential Areas for Minor Clarification:**

*   The existence of both `Server` and `McpServer` might initially confuse users, but the README explains `McpServer` as the higher-level abstraction.
*   WebSocket server support is not present, only client-side. This seems intentional based on the file structure.
*   The `CLAUDE.md` file appears to be internal developer notes rather than public documentation.

**Conclusion:**

This is a well-designed and comprehensive SDK for the Model Context Protocol. It provides robust implementations for both clients and servers, supports multiple transport mechanisms (with a clear preference for Streamable HTTP), and includes advanced features necessary for real-world applications, such as authentication, dynamic capabilities, and resumability. The use of Zod ensures type safety and protocol adherence. The documentation and examples are strong, making it a solid foundation for developers looking to integrate with or build MCP-based systems.