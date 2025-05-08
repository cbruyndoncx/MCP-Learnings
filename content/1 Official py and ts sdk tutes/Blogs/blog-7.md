---
title: "Blog 7: The Modern Web - Streamable HTTP, Resumability, and Backwards Compatibility"
draft: false
---
## Blog 7: The Modern Web - Streamable HTTP, Resumability, and Backwards Compatibility

**Series:** Deep Dive into the Model Context Protocol SDKs (TypeScript & Python)
**Post:** 7 of 10

In [Blog 6](blog-6.md), we examined the Stdio transport for local communication and the foundational HTTP+SSE transport prevalent in the Python MCP SDK. While functional, the dual-endpoint nature of HTTP+SSE presents certain complexities for web-based interactions.

The TypeScript SDK, aligning with newer iterations of the MCP specification (like `2025-03-26`), champions a more streamlined approach for HTTP: **Streamable HTTP**. This transport aims to simplify communication, enhance efficiency, and introduce powerful features like resumability.

This post dives into:

1.  The **Streamable HTTP** transport (primarily focusing on the TypeScript implementation).
2.  Its key features: single endpoint, session management (stateful/stateless), JSON response mode, and **resumability**.
3.  Strategies for **Backwards Compatibility** enabling modern clients/servers to interoperate with older ones using HTTP+SSE.
4.  Comparing Streamable HTTP with Python's SSE-based approach.

### Streamable HTTP: A Unified Approach (TypeScript Focus)

Defined primarily in the TypeScript SDK (`src/client/streamableHttp.ts`, `src/server/streamableHttp.ts`), the Streamable HTTP transport consolidates MCP communication over a *single* HTTP endpoint, typically `/mcp`. It elegantly handles different interaction patterns using standard HTTP methods:

*   **`POST`:** Used by the client to send requests and notifications *to* the server.
    *   The `Accept` header *must* include both `application/json` and `text/event-stream`.
    *   The server can respond in two ways:
        1.  **SSE Stream (`Content-Type: text/event-stream`):** The server streams back JSON-RPC responses and subsequent server-initiated notifications related to the *original* request(s) in the POST body. This is the preferred method for long-running operations or when notifications are expected.
        2.  **Direct JSON (`Content-Type: application/json`):** The server sends back all JSON-RPC responses directly in the POST response body (either a single object or a batch array). Used for simpler request-response cycles or when the server explicitly disables SSE (`enableJsonResponse: true`).
        3.  **`202 Accepted`:** If the client sends *only* notifications (no requests needing a response), the server replies with `202` and no body.
*   **`GET`:** Used by the client *optionally* to establish a standalone, long-lived SSE stream for receiving *unsolicited* server-initiated notifications (e.g., `resourceListChanged`, `logMessage`).
    *   Requires `Accept: text/event-stream`.
    *   The server *may* support this, responding with an SSE stream or `405 Method Not Allowed`.
*   **`DELETE`:** Used by the client to explicitly terminate its session with the server.
    *   Requires the `Mcp-Session-Id` header.
    *   Server responds `200 OK` on success or `405 Method Not Allowed` if termination isn't supported/allowed.

**Key Implementation (`StreamableHTTPServerTransport` - TS):**

*   **`handleRequest(req, res, parsedBody?)`:** A single method routes incoming Express `req`/`res` objects based on the HTTP method (`req.method`) to the appropriate internal handler (`handlePostRequest`, `handleGetRequest`, `handleDeleteRequest`). It can optionally accept a pre-parsed body.
*   **Session Management:**
    *   **Stateful (Default):** If `sessionIdGenerator` is provided (e.g., `() => randomUUID()`), the transport manages sessions. The first `initialize` POST response includes a generated `Mcp-Session-Id` header. Subsequent requests *must* include this header, and the transport validates it. It maintains internal state mapping session IDs to connections (`_streamMapping`).
    *   **Stateless:** If `sessionIdGenerator` is `undefined`, session management is disabled. No session IDs are generated or validated (though an ID might still be sent on the *initial* response if the client provided one, for compatibility). Each request is treated independently.
*   **Response Handling:** Tracks pending requests (`_requestToStreamMapping`, `_requestResponseMap`). Sends responses via the appropriate SSE stream (POST-bound or GET-bound) or collects them for a single JSON response if `enableJsonResponse` is true.
*   **Resumability (`EventStore`):** If an `EventStore` implementation is provided during construction, the transport automatically:
    *   Stores outgoing server messages (responses/notifications) with unique, sequential `EventId`s associated with a `StreamId` (session/connection identifier).
    *   Includes the `id: <EventId>` field in SSE events sent to the client.
    *   Handles incoming `GET` or `POST` requests containing a `Last-Event-ID` header by querying the `EventStore` (`replayEventsAfter`) to resend any messages the client missed since that ID.

```typescript
// Server-side Streamable HTTP (TypeScript Example)
import express from "express";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { InMemoryEventStore } from "../examples/shared/inMemoryEventStore.js"; // Example store
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { randomUUID } from "node:crypto";

const app = express();
app.use(express.json()); // Needed if not using pre-parsed body

const transports: { [sessionId: string]: StreamableHTTPServerTransport } = {}; // Store transports

const mcpServer = new McpServer(/* ... server info ... */);

// Single endpoint handles all methods
app.all('/mcp', async (req, res) => {
  const sessionId = req.headers['mcp-session-id'] as string | undefined;
  let transport: StreamableHTTPServerTransport;

  if (sessionId && transports[sessionId]) {
    transport = transports[sessionId];
  } else if (req.method === 'POST' && isInitializeRequest(req.body)) {
    // New connection, create transport (stateful with resumability)
    const eventStore = new InMemoryEventStore();
    transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: () => randomUUID(), // Stateful
      eventStore: eventStore,                // Enable resumability
      onsessioninitialized: (newSessionId) => {
         transports[newSessionId] = transport; // Store *after* init
         console.log(`Session ${newSessionId} initialized.`);
      }
    });
    await mcpServer.connect(transport); // Connect McpServer logic
    // onclose handler needed to remove from 'transports' map
    transport.onclose = () => {
      if (transport.sessionId) delete transports[transport.sessionId];
    }
  } else {
     // Handle error: Invalid session or non-init request without session
     res.status(400).json({ /* ... error object ... */ });
     return;
  }

  // Let the transport handle routing based on method (GET/POST/DELETE)
  // Pass req.body if using express.json() middleware
  await transport.handleRequest(req, res, req.body);
});

app.listen(3000);
```

**Client Implementation (`StreamableHTTPClientTransport` - TS):**

*   Uses `fetch` for all interactions (GET, POST, DELETE).
*   Sends appropriate `Accept` and `Content-Type` headers.
*   Stores the `Mcp-Session-Id` received from the server after `initialize` and includes it in subsequent requests.
*   Parses `Content-Type` of POST responses to determine if it's JSON or an SSE stream.
*   Handles SSE streams using `EventSourceParserStream`.
*   Manages an optional standalone GET SSE stream for server notifications.
*   Implements reconnection logic with exponential backoff for the GET stream.
*   Supports resumability by optionally tracking the `Last-Event-ID` received and sending it on reconnect attempts or subsequent POSTs (`resumptionToken` option in `send`).

### Killer Feature: Resumability

Streamable HTTP's integration with an `EventStore` enables powerful resumability, particularly useful for:

*   **Long-running Tools:** If a client calls a tool that takes minutes and sends many progress notifications, the connection might drop.
*   **Network Glitches:** Temporary network issues can interrupt the SSE stream.

**How it works:**

1.  **Server:** Assigns a unique, ordered `EventId` to every message sent over SSE (responses and notifications). Stores `(StreamId, EventId, Message)` in the `EventStore`.
2.  **Client:** Receives messages with `id: <EventId>` lines in the SSE stream. It keeps track of the *last seen* `EventId`.
3.  **Disconnection:** The connection drops.
4.  **Client Reconnection:** The client reconnects (either via `GET` or the next `POST`) and includes the `Last-Event-ID: <last_seen_event_id>` header.
5.  **Server:** Receives the request with `Last-Event-ID`. It queries the `EventStore`'s `replayEventsAfter(<last_seen_event_id>)` method.
6.  **EventStore:** Finds all messages for that stream *after* the provided `EventId`.
7.  **Server:** Sends the missed messages (with their original `EventId`s) down the *new* connection before sending any *new* messages.

This ensures the client seamlessly catches up without missing intermediate notifications or responses from long-running tasks, providing a much smoother user experience. The `InMemoryEventStore` (`src/examples/shared/inMemoryEventStore.ts`) provides a basic implementation, but production systems would use a persistent database (Redis, PostgreSQL, etc.).

### Backwards Compatibility: Bridging the Transport Gap

Since not all clients and servers will upgrade simultaneously, the MCP specification and the SDKs provide guidance for interoperability between Streamable HTTP and the older HTTP+SSE transport.

**Client Strategy (Modern Client, Old Server):**

As detailed in the TypeScript SDK's `streamableHttpWithSseFallbackClient.ts` example:

1.  **Try Modern First:** The client first attempts an `initialize` request via `POST` to the server's base URL (e.g., `/mcp`).
2.  **Check Response:**
    *   If the server responds `200 OK` (with `Content-Type: text/event-stream` or `application/json`) and potentially an `Mcp-Session-Id`, the client proceeds using the Streamable HTTP transport logic.
    *   If the server responds with a `4xx` error (like `405 Method Not Allowed` or `404 Not Found`), the client assumes it's an older server.
3.  **Fallback to SSE:** The client then initiates a `GET` request to the *same* base URL (or potentially a dedicated `/sse` path if known). If successful, it expects the `endpoint` event and proceeds using the classic HTTP+SSE logic (sending messages via `POST` to the endpoint URL with `?session_id=...`).

**Server Strategy (Modern Server, Old Client):**

As detailed in the TypeScript SDK's `sseAndStreamableHttpCompatibleServer.ts` example:

1.  **Support Both Endpoint Styles:** The server listens on *both* the single Streamable HTTP endpoint (e.g., `/mcp` for GET/POST/DELETE) *and* the older separate endpoints (e.g., `/sse` for GET, `/messages` for POST).
2.  **Transport Detection:** When a connection is initiated:
    *   If it's a `POST` to `/mcp` for `initialize` or any request with `Mcp-Session-Id`, use `StreamableHTTPServerTransport`.
    *   If it's a `GET` to `/sse`, use `SSEServerTransport`.
    *   If it's a `POST` to `/messages` with `?session_id=...`, look up the existing `SSEServerTransport` for that session.
3.  **Session State:** Maintain separate session state or transport instances based on the protocol detected for a given session ID to avoid mixing behaviors.

This allows a modern server to gracefully handle connections from both new and legacy clients.

### Comparison: Streamable HTTP (TS) vs. SSE (Python)

| Feature           | Streamable HTTP (TS)                 | HTTP+SSE (Python)                     | Notes                                                                                                 |
| :---------------- | :----------------------------------- | :------------------------------------ | :---------------------------------------------------------------------------------------------------- |
| **Endpoints**     | Single (e.g., `/mcp`)                | Two (e.g., `/sse`, `/messages`)       | Streamable HTTP is simpler architecturally.                                                           |
| **Request Method**| `POST`                               | `POST`                                | Client-to-server messages use POST in both.                                                         |
| **Response Method**| `POST` (SSE Stream or JSON), `GET` (SSE Stream) | `GET` (SSE Stream only)             | Streamable HTTP offers more flexibility in response delivery (direct JSON vs. SSE on POST).         |
| **Session Mgmt**  | Built-in (Stateful/Stateless)        | Implicit via `session_id` query param | Streamable HTTP has explicit stateful/stateless modes. SSE relies on the client passing the correct ID. |
| **Resumability**  | Yes (via `EventStore`, `Last-Event-ID`) | No (Protocol inherent limitation)   | Major advantage for Streamable HTTP, crucial for long tasks/unreliable networks.                 |
| **Complexity**    | Slightly more complex server logic   | Simpler server logic                  | Handling multiple response types/methods on one endpoint adds some complexity for Streamable HTTP. |
| **SDK Support**   | Primary in TS                        | Primary in Python                     | Clear divergence in the preferred HTTP transport between the SDKs.                             |

### Conclusion

Streamable HTTP represents a significant evolution in MCP's web transport capabilities, offering a unified endpoint, flexible response modes, and robust resumability. The TypeScript SDK provides a comprehensive implementation, showcasing its advantages, particularly for complex, long-running interactions over potentially unreliable networks.

While the Python SDK currently favors the established HTTP+SSE model, the clear specifications and examples for backwards compatibility ensure that applications built with either SDK can still communicate effectively during transition periods. Understanding both transports is key for developers working in mixed-language MCP environments or migrating existing applications.

In our next post, we'll tackle **Blog 8: Securing Interactions - Authentication (OAuth Focus)**, investigating how the SDKs approach securing MCP communication.

---
