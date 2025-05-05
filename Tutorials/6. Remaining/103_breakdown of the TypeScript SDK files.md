Okay, here's a breakdown of the TypeScript SDK files, ordered approximately from least dependent on other files *within this specific SDK repository* to most dependent, along with their purposes.

**Level 0: Foundational Definitions & Self-Contained Utilities**

1.  `src/types.ts`:
    *   **Purpose:** **THE foundational definitions.** Defines all MCP message structures (Requests, Responses, Notifications, Primitives like Tool, Resource, Prompt, Content types, Capabilities, etc.) using Zod schemas. Derives corresponding TypeScript types using `z.infer`. Defines protocol constants (`LATEST_PROTOCOL_VERSION`, `JSONRPC_VERSION`) and error codes (`ErrorCode`).
    *   **Dependencies:** Zod (external). Minimal internal dependencies, potentially simple enums/types from itself.
2.  `src/shared/transport.ts`:
    *   **Purpose:** Defines the abstract `Transport` interface contract (methods `start`, `send`, `close`, callbacks `onmessage`, `onclose`, `onerror`) and `TransportSendOptions`.
    *   **Dependencies:** `types.ts` (for `JSONRPCMessage`, `RequestId`, `AuthInfo`). Minimal implementation.
3.  `src/shared/stdio.ts`:
    *   **Purpose:** Provides utilities specific to newline-delimited JSON framing for the Stdio transport (`ReadBuffer`, `serializeMessage`, `deserializeMessage`).
    *   **Dependencies:** `types.ts` (for `JSONRPCMessage`, `JSONRPCMessageSchema`).
4.  `src/shared/uriTemplate.ts`:
    *   **Purpose:** Implements RFC 6570 URI Template parsing and expansion. Used for dynamic resources.
    *   **Dependencies:** None internal (standard JS/TS APIs).
5.  `src/server/auth/types.ts`:
    *   **Purpose:** Defines the `AuthInfo` interface used to represent validated authentication context passed to handlers.
    *   **Dependencies:** None internal.
6.  `src/shared/auth.ts`:
    *   **Purpose:** Defines shared Zod schemas for standard OAuth 2.1 data structures (Tokens, Metadata, Client Info, Errors) used by both client and server auth components.
    *   **Dependencies:** Zod (external).
7.  `src/server/auth/errors.ts`:
    *   **Purpose:** Defines custom Error subclasses for specific OAuth errors (e.g., `InvalidRequestError`, `InvalidClientError`), inheriting from a base `OAuthError`.
    *   **Dependencies:** Base `Error`.

**Level 1: Core Protocol Logic**

8.  `src/shared/protocol.ts`:
    *   **Purpose:** Implements the abstract `Protocol` base class. Contains the core JSON-RPC message handling logic: request/response correlation, ID management, notification dispatch, timeout handling (`DEFAULT_REQUEST_TIMEOUT_MSEC`, `RequestOptions`), cancellation, progress notification processing. Defines `RequestHandlerExtra`.
    *   **Dependencies:** `types.ts`, `shared/transport.ts`, `server/auth/types.ts`.

**Level 2: Base Client/Server Implementations**

9.  `src/client/index.ts`:
    *   **Purpose:** Defines the primary `Client` class. Extends `Protocol`. Implements the client-side initialization handshake, capability checking against server capabilities, and provides high-level methods (`ping`, `listTools`, `callTool`, `readResource`, `getPrompt`, `setLoggingLevel`, etc.) which wrap `protocol.request`. Defines `ClientOptions`.
    *   **Dependencies:** `shared/protocol.ts`, `types.ts`, `shared/transport.ts`.
10. `src/server/index.ts`:
    *   **Purpose:** Defines the low-level `Server` class. Extends `Protocol`. Implements the server-side initialization handshake response, capability checking against client capabilities, and provides `setRequestHandler`/`setNotificationHandler` for registering logic for specific MCP methods using Zod schemas. Defines `ServerOptions`.
    *   **Dependencies:** `shared/protocol.ts`, `types.ts`, `shared/transport.ts`.

**Level 3: Concrete Transport Implementations**

11. `src/inMemory.ts`:
    *   **Purpose:** Implements the `Transport` interface for testing client/server interactions entirely within memory using shared queues. Includes `createLinkedPair`.
    *   **Dependencies:** `shared/transport.ts`, `types.ts`, `server/auth/types.ts`.
12. `src/client/stdio.ts`:
    *   **Purpose:** Implements `Transport` for the client side of Stdio communication. Manages spawning and communicating with a child process using `cross-spawn`. Includes `StdioClientTransportOptions` and `getDefaultEnvironment`.
    *   **Dependencies:** `shared/transport.ts`, `shared/stdio.ts`, `types.ts`, `cross-spawn` (external).
13. `src/server/stdio.ts`:
    *   **Purpose:** Implements `Transport` for the server side of Stdio communication. Reads from `process.stdin` and writes to `process.stdout`.
    *   **Dependencies:** `shared/transport.ts`, `shared/stdio.ts`, `types.ts`.
14. `src/client/websocket.ts`:
    *   **Purpose:** Implements `Transport` for client-side WebSocket communication. Uses the `ws` library.
    *   **Dependencies:** `shared/transport.ts`, `types.ts`, `ws` (external).
15. `src/client/auth.ts`:
    *   **Purpose:** Provides client-side helper functions for initiating OAuth 2.1 flows (discovery, start auth, exchange code, refresh token, register client). Uses `fetch` and `pkce-challenge`.
    *   **Dependencies:** `shared/auth.ts`, `types.ts` (for `LATEST_PROTOCOL_VERSION`), `pkce-challenge` (external/mocked).
16. `src/client/sse.ts`:
    *   **Purpose:** Implements `Transport` for the *legacy* HTTP+SSE client (dual endpoint: GET `/sse`, POST `/message`). Includes optional OAuth handling via `authProvider` option.
    *   **Dependencies:** `shared/transport.ts`, `types.ts`, `client/auth.ts`, `eventsource` (external).
17. `src/server/sse.ts`:
    *   **Purpose:** Implements `Transport` for the *legacy* HTTP+SSE server. Handles the `GET /sse` stream (using Node `http.ServerResponse`) and `POST /message` requests (parsing body, using `sessionId` query param).
    *   **Dependencies:** `shared/transport.ts`, `types.ts`, `server/auth/types.ts`, Node `http`, `crypto`, `url`, `content-type`, `raw-body` (external).
18. `src/client/streamableHttp.ts`:
    *   **Purpose:** Implements `Transport` for the *modern* Streamable HTTP client (single endpoint GET/POST). Handles SSE/JSON responses, header-based sessions, `Last-Event-ID` for resumability, reconnection logic. Includes optional OAuth handling via `authProvider`.
    *   **Dependencies:** `shared/transport.ts`, `types.ts`, `client/auth.ts`, `eventsource-parser/stream` (external).
19. `src/server/streamableHttp.ts`:
    *   **Purpose:** Implements `Transport` for the *modern* Streamable HTTP server. Handles GET/POST/DELETE on a single endpoint, manages sessions via `Mcp-Session-Id` header, supports SSE/JSON response modes, implements resumability via the `EventStore` interface.
    *   **Dependencies:** `shared/transport.ts`, `types.ts`, `server/auth/types.ts`, Node `http`, `crypto`, `content-type`, `raw-body` (external). Defines `EventStore`, `StreamableHTTPServerTransportOptions`.

**Level 4: High-Level Server Abstractions & OAuth Implementation**

20. `src/server/completable.ts`:
    *   **Purpose:** Defines the `Completable` Zod schema wrapper and related types used to add autocompletion logic to tool/prompt arguments.
    *   **Dependencies:** Zod (external).
21. `src/server/mcp.ts`:
    *   **Purpose:** Defines the high-level `McpServer` class. Provides ergonomic `.tool()`, `.resource()`, `.prompt()` methods for registering primitives. Wraps the low-level `Server`, automatically setting up handlers and generating schemas (`zod-to-json-schema`). Returns handles (`RegisteredTool`, etc.) for dynamic management. Defines `ResourceTemplate`.
    *   **Dependencies:** `server/index.ts`, `types.ts`, Zod, `zod-to-json-schema` (external), `server/completable.ts`, `shared/uriTemplate.ts`.
22. `src/server/auth/clients.ts`:
    *   **Purpose:** Defines the `OAuthRegisteredClientsStore` interface contract for storing/retrieving OAuth client registrations.
    *   **Dependencies:** `shared/auth.ts`.
23. `src/server/auth/provider.ts`:
    *   **Purpose:** Defines the `OAuthServerProvider` interface contract, outlining the methods needed to implement the core OAuth logic (authorize, exchange tokens, verify tokens, revoke).
    *   **Dependencies:** Express types (external), `server/auth/clients.ts`, `shared/auth.ts`, `server/auth/types.ts`.
24. `src/server/auth/middleware/allowedMethods.ts`:
    *   **Purpose:** Express middleware to reject requests using disallowed HTTP methods for an endpoint.
    *   **Dependencies:** Express types (external), `server/auth/errors.ts`.
25. `src/server/auth/middleware/clientAuth.ts`:
    *   **Purpose:** Express middleware to authenticate an OAuth client based on `client_id` and `client_secret` in the request body (for `/token`, `/revoke` endpoints). Attaches `req.client`.
    *   **Dependencies:** Express types (external), Zod, `server/auth/clients.ts`, `shared/auth.ts`, `server/auth/errors.ts`.
26. `src/server/auth/middleware/bearerAuth.ts`:
    *   **Purpose:** Express middleware to authenticate requests using a Bearer token in the `Authorization` header. Validates the token using the `OAuthServerProvider` and attaches `req.auth`. Used to protect MCP endpoints.
    *   **Dependencies:** Express types (external), `server/auth/provider.ts`, `server/auth/errors.ts`, `server/auth/types.ts`.
27. `src/server/auth/handlers/*.ts` (authorize, metadata, register, revoke, token):
    *   **Purpose:** Implement the request handling logic for each standard OAuth endpoint (`/authorize`, `/.well-known/...`, `/register`, `/revoke`, `/token`). They parse requests, apply middleware (like `authenticateClient`), call the appropriate `OAuthServerProvider` methods, and format responses.
    *   **Dependencies:** Express types (external), `server/auth/provider.ts`, middleware, errors, shared types, Zod.
28. `src/server/auth/providers/proxyProvider.ts`:
    *   **Purpose:** Provides a concrete implementation of `OAuthServerProvider` that proxies requests to an upstream OAuth server.
    *   **Dependencies:** `server/auth/provider.ts`, `server/auth/clients.ts`, `shared/auth.ts`, `server/auth/errors.ts`, `fetch` (likely via Node or polyfill).

**Level 5: Top-Level Integration & Examples**

29. `src/server/auth/router.ts`:
    *   **Purpose:** Provides the `mcpAuthRouter` function, which conveniently creates and configures an Express router with all the standard OAuth endpoint handlers and middleware, wired to a given `OAuthServerProvider`.
    *   **Dependencies:** Express (external), all files in `server/auth/handlers/` and `server/auth/middleware/`, `server/auth/provider.ts`.
30. `src/cli.ts`:
    *   **Purpose:** A simple command-line interface for running basic client/server examples, primarily using Stdio but also demonstrating SSE/WebSocket client connection.
    *   **Dependencies:** `client/index.ts`, `server/index.ts`, various transport implementations, `types.ts`, `ws` (external).
31. `src/examples/**/*.ts`:
    *   **Purpose:** Practical examples demonstrating how to build clients and servers using the SDK, showcasing features like different transports, state management, resumability, and parallel operations.
    *   **Dependencies:** Various core client/server classes (`Client`, `McpServer`), transports, types.
32. `src/integration-tests/**/*.ts`:
    *   **Purpose:** Tests designed to verify the interaction between client and server components, often involving real (but controlled) transports or specific feature interactions like resumability.
    *   **Dependencies:** Core client/server classes, transports, types, testing framework (Jest).
33. `src/**/*.test.ts` (Unit Tests):
    *   **Purpose:** Test individual classes or functions in isolation.
    *   **Dependencies:** The specific unit under test, mocking libraries (Jest), potentially `inMemory.ts`.

This ordering flows from foundational type definitions and utilities -> core protocol logic -> client/server base classes -> specific communication transports -> high-level abstractions -> complex features like OAuth -> top-level entry points, examples, and tests.