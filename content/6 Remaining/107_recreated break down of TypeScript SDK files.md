Okay, let's break down the TypeScript SDK files, ordering them from the most foundational and least dependent on other internal SDK files, up to the most complex and highly dependent components like examples and tests.

---

**Level 0: Foundational Definitions & Self-Contained Utilities**

These files define core types or provide basic utilities with minimal reliance on other SDK modules, mostly depending on external libraries (like Zod) or built-in language features.

1.  `src/types.ts`:
    *   **Purpose:** **The absolute core.** Defines all Model Context Protocol message structures (Requests, Responses, Notifications), data types (Tool, Resource, Prompt, Content variants), capability flags, error codes, and protocol constants using Zod schemas. It derives the corresponding TypeScript types using `z.infer`. This file is the foundational contract for the entire SDK.
    *   **Dependencies:** Zod (external).

2.  `src/shared/transport.ts`:
    *   **Purpose:** Defines the essential `Transport` interface contract. Specifies the methods (`start`, `send`, `close`) and callbacks (`onmessage`, `onclose`, `onerror`) that any communication mechanism must implement to be used by the core protocol logic. Also defines `TransportSendOptions`.
    *   **Dependencies:** `types.ts` (for `JSONRPCMessage`, `RequestId`, `AuthInfo`).

3.  `src/shared/stdio.ts`:
    *   **Purpose:** Provides utility functions (`serializeMessage`, `deserializeMessage`) and the `ReadBuffer` class specifically for handling the newline-delimited JSON framing required by the Stdio transport.
    *   **Dependencies:** `types.ts` (for `JSONRPCMessage`, `JSONRPCMessageSchema`).

4.  `src/shared/uriTemplate.ts`:
    *   **Purpose:** Implements URI Template (RFC 6570) parsing and expansion logic. Essential for handling dynamic resource URIs (e.g., `items://{category}/{id}`).
    *   **Dependencies:** None internal (uses standard TS/JS APIs).

5.  `src/server/auth/types.ts`:
    *   **Purpose:** Defines the `AuthInfo` interface, which represents the validated authentication context (token, client ID, scopes) passed to request handlers when using bearer authentication.
    *   **Dependencies:** None internal.

6.  `src/shared/auth.ts`:
    *   **Purpose:** Defines shared Zod schemas for standard OAuth 2.1 data structures (like `OAuthTokens`, `OAuthMetadata`, `OAuthClientInformation`, `OAuthErrorResponse`) used by both client-side helpers and server-side implementation.
    *   **Dependencies:** Zod (external).

7.  `src/server/auth/errors.ts`:
    *   **Purpose:** Defines specific `Error` subclasses (e.g., `InvalidRequestError`, `InvalidClientError`, `InvalidTokenError`) extending a base `OAuthError` for representing standard OAuth 2.1 error conditions. Includes logic to format these into OAuth error responses.
    *   **Dependencies:** Base `Error`.

**Level 1: Core Protocol Logic**

8.  `src/shared/protocol.ts`:
    *   **Purpose:** Implements the abstract `Protocol` class, the engine driving MCP communication. It manages the session lifecycle over a `Transport`, handles JSON-RPC request/response correlation via IDs, dispatches incoming messages to registered handlers, manages request timeouts and cancellation (`AbortSignal`), processes progress notifications, and defines `RequestHandlerExtra`. It's the base for both `Client` and `Server`.
    *   **Dependencies:** `types.ts`, `shared/transport.ts`, `server/auth/types.ts`.

**Level 2: Base Client/Server Implementations**

9.  `src/client/index.ts`:
    *   **Purpose:** Defines the primary public `Client` class. It extends `Protocol`, specializing it for client-side behavior. It implements the client part of the `initialize` handshake, stores server capabilities, checks *server* capabilities before sending requests (if strict), and provides high-level async methods (`listTools`, `callTool`, `readResource`, `getPrompt`, etc.) that wrap the core `protocol.request` logic. Defines `ClientOptions`.
    *   **Dependencies:** `shared/protocol.ts`, `types.ts`, `shared/transport.ts`.

10. `src/server/index.ts`:
    *   **Purpose:** Defines the low-level `Server` class. Extends `Protocol`, specializing for server-side behavior. Implements the server part of the `initialize` handshake (responding to the client), stores client capabilities, checks *client* capabilities before sending requests (if strict), and provides the fundamental `setRequestHandler` and `setNotificationHandler` methods for registering custom logic using Zod schemas for validation. Defines `ServerOptions`.
    *   **Dependencies:** `shared/protocol.ts`, `types.ts`, `shared/transport.ts`.

**Level 3: Concrete Transport Implementations**

These classes implement the `Transport` interface for specific communication channels.

11. `src/inMemory.ts`:
    *   **Purpose:** Implements `Transport` for testing. Uses internal queues to connect a client and server directly in memory. Provides `createLinkedPair` static method.
    *   **Dependencies:** `shared/transport.ts`, `types.ts`, `server/auth/types.ts`.

12. `src/client/stdio.ts`:
    *   **Purpose:** Client-side `Transport` for Stdio. Uses `cross-spawn` to launch the server process, manages its lifecycle, and communicates via its stdin/stdout streams using helpers from `shared/stdio.ts`. Defines `StdioClientTransportOptions`.
    *   **Dependencies:** `shared/transport.ts`, `shared/stdio.ts`, `types.ts`, `cross-spawn` (external).

13. `src/server/stdio.ts`:
    *   **Purpose:** Server-side `Transport` for Stdio. Assumes it's the running process. Reads from `process.stdin` and writes to `process.stdout` using helpers from `shared/stdio.ts`.
    *   **Dependencies:** `shared/transport.ts`, `shared/stdio.ts`, `types.ts`, Node `process`.

14. `src/client/websocket.ts`:
    *   **Purpose:** Client-side `Transport` for WebSocket. Uses the `ws` library to connect and exchange messages according to the `mcp` subprotocol expectation.
    *   **Dependencies:** `shared/transport.ts`, `types.ts`, `ws` (external).

15. `src/client/auth.ts`:
    *   **Purpose:** Provides **client-side helper functions** (not a transport itself) for executing standard OAuth 2.1 flows against an MCP server's auth endpoints (e.g., discovery, authorization request generation, code exchange, token refresh, dynamic client registration). Uses `fetch`.
    *   **Dependencies:** `shared/auth.ts`, `types.ts` (for `LATEST_PROTOCOL_VERSION`), `pkce-challenge` (external/mocked for tests).

16. `src/client/sse.ts`:
    *   **Purpose:** Implements `Transport` for the **legacy** HTTP+SSE client (dual endpoint). Handles the `GET /sse` stream (using `eventsource`) and sending `POST /message?sessionId=...`. Includes optional integration with `client/auth.ts` for adding Bearer tokens.
    *   **Dependencies:** `shared/transport.ts`, `types.ts`, `client/auth.ts`, `eventsource` (external).

17. `src/server/sse.ts`:
    *   **Purpose:** Implements `Transport` for the **legacy** HTTP+SSE server. Handles `GET /sse` (managing `http.ServerResponse` for SSE) and `POST /message` (parsing body, routing via `sessionId` query parameter).
    *   **Dependencies:** `shared/transport.ts`, `types.ts`, `server/auth/types.ts`, Node `http`, `crypto`, `url`, `content-type` (external), `raw-body` (external).

18. `src/client/streamableHttp.ts`:
    *   **Purpose:** Implements `Transport` for the **modern** Streamable HTTP client. Uses `fetch` for single-endpoint GET/POST/DELETE. Handles both SSE and direct JSON responses on POST. Manages `Mcp-Session-Id` header. Implements reconnection logic and `Last-Event-ID` for resumability. Includes optional integration with `client/auth.ts`.
    *   **Dependencies:** `shared/transport.ts`, `types.ts`, `client/auth.ts`, `eventsource-parser/stream` (external).

19. `src/server/streamableHttp.ts`:
    *   **Purpose:** Implements `Transport` for the **modern** Streamable HTTP server. Handles GET/POST/DELETE on a single endpoint. Manages sessions via `Mcp-Session-Id` header. Supports SSE/JSON response modes. Implements resumability by interacting with the `EventStore` interface (defined within).
    *   **Dependencies:** `shared/transport.ts`, `types.ts`, `server/auth/types.ts`, Node `http`, `crypto`, `content-type` (external), `raw-body` (external). Defines `StreamableHTTPServerTransportOptions`, `EventStore`.

**Level 4: High-Level Server Abstractions & OAuth Implementation**

These build significantly upon the lower-level components.

20. `src/server/completable.ts`:
    *   **Purpose:** Defines the `Completable` Zod schema wrapper. This allows attaching a completion function to a schema definition, used by `McpServer` for argument autocompletion.
    *   **Dependencies:** Zod (external).

21. `src/server/mcp.ts`:
    *   **Purpose:** Defines the high-level `McpServer` class, the primary ergonomic API for *building* servers. Provides `.tool()`, `.resource()`, `.prompt()` methods for declarative registration. It wraps the low-level `Server`, automatically generating schemas (using `zod-to-json-schema`), registering handlers, and managing dynamic updates via returned handles (`RegisteredTool`, etc.). Defines `ResourceTemplate`.
    *   **Dependencies:** `server/index.ts` (low-level Server), `types.ts`, Zod, `zod-to-json-schema` (external), `server/completable.ts`, `shared/uriTemplate.ts`.

22. `src/server/auth/clients.ts`:
    *   **Purpose:** Defines the `OAuthRegisteredClientsStore` interface, the contract for how the OAuth server stores and retrieves information about registered client applications.
    *   **Dependencies:** `shared/auth.ts`.

23. `src/server/auth/provider.ts`:
    *   **Purpose:** Defines the `OAuthServerProvider` interface, the core contract for implementing the actual OAuth logic (user authorization, code/token exchange, token validation, revocation). This is what developers would implement or use (like `ProxyOAuthServerProvider`).
    *   **Dependencies:** Express types (external, for `Response`), `server/auth/clients.ts`, `shared/auth.ts`, `server/auth/types.ts`.

24. `src/server/auth/middleware/allowedMethods.ts`:
    *   **Purpose:** Utility Express middleware to restrict HTTP methods allowed for a route, returning 405 otherwise.
    *   **Dependencies:** Express types (external), `server/auth/errors.ts`.

25. `src/server/auth/middleware/clientAuth.ts`:
    *   **Purpose:** Express middleware for authenticating OAuth clients via `client_id`/`client_secret` in the request body (used by `/token`, `/revoke`). It uses the `OAuthRegisteredClientsStore` to validate credentials and attaches the client info to `req.client`.
    *   **Dependencies:** Express types (external), Zod, `server/auth/clients.ts`, `shared/auth.ts`, `server/auth/errors.ts`.

26. `src/server/auth/middleware/bearerAuth.ts`:
    *   **Purpose:** Critical Express middleware for protecting MCP endpoints. It extracts the Bearer token from the `Authorization` header, validates it using the `OAuthServerProvider.verifyAccessToken`, checks scopes/expiration, and attaches the resulting `AuthInfo` to `req.auth`.
    *   **Dependencies:** Express types (external), `server/auth/provider.ts`, `server/auth/errors.ts`, `server/auth/types.ts`.

27. `src/server/auth/handlers/*.ts` (authorize.ts, metadata.ts, register.ts, revoke.ts, token.ts):
    *   **Purpose:** These implement the specific logic for each standard OAuth endpoint. They parse requests using Zod/schemas, apply necessary middleware (`authenticateClient`), interact with the `OAuthServerProvider` to perform the core logic (e.g., `provider.exchangeAuthorizationCode`), and format appropriate OAuth success or error responses.
    *   **Dependencies:** Express types (external), `server/auth/provider.ts`, relevant middleware (`clientAuth`), errors, shared types, Zod, `pkce-challenge` (token handler).

28. `src/server/auth/providers/proxyProvider.ts`:
    *   **Purpose:** A concrete implementation of `OAuthServerProvider` that acts as a proxy, forwarding requests to an upstream OAuth server. Implements the required provider methods by making `fetch` calls to the configured upstream endpoints.
    *   **Dependencies:** `server/auth/provider.ts`, `server/auth/clients.ts` (for its own client store interface), `shared/auth.ts`, `server/auth/errors.ts`.

**Level 5: Top-Level Integration, Examples & Tests**

29. `src/server/auth/router.ts`:
    *   **Purpose:** Provides the `mcpAuthRouter` factory function. This is a major convenience function that takes an `OAuthServerProvider` implementation and wires up an Express router with all the standard OAuth endpoint handlers and middleware configured correctly.
    *   **Dependencies:** Express (external), all files in `server/auth/handlers/`, `server/auth/middleware/`, `server/auth/provider.ts`.

30. `src/cli.ts`:
    *   **Purpose:** A basic command-line tool to run simple client/server examples provided in the SDK, primarily for testing Stdio but demonstrating other transports too.
    *   **Dependencies:** `client/index.ts`, `server/index.ts`, various transport implementations (`Stdio`, `SSE`, `WebSocket`), `types.ts`, `ws` (external).

31. `src/examples/**/*.ts`:
    *   **Purpose:** Provides practical, runnable examples demonstrating various ways to use the SDK to build clients and servers (different transports, stateful/stateless, resumability, parallel calls, etc.). These are key learning resources.
    *   **Dependencies:** Core SDK classes (`Client`, `McpServer`), specific transports, `types.ts`, Node `crypto`, `express` (external).

32. `src/integration-tests/**/*.ts`:
    *   **Purpose:** Contains tests that verify the interaction *between* different components, often client and server, sometimes involving real transports (like launching a Stdio process) or specific features like resumability with an `InMemoryEventStore`.
    *   **Dependencies:** Core SDK classes, transports, types, testing framework (Jest), potentially example code (`InMemoryEventStore`).

33. `src/**/*.test.ts` (Unit Tests):
    *   **Purpose:** Test individual classes, functions, or modules in isolation. Validate logic, error handling, and edge cases.
    *   **Dependencies:** The specific file/unit under test, mocking libraries (Jest built-ins, potentially others), maybe `inMemory.ts` for simple transport mocking. Highest dependency level as they test everything else.

This detailed hierarchy flows from the most basic type definitions up through core logic, transports, abstractions, complex features like authentication, and finally the usage examples and tests that integrate everything.