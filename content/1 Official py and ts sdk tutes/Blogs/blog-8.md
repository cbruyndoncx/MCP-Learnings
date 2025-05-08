---
title: "Blog 8: Securing Interactions - Authentication in MCP SDKs (OAuth Focus)"
draft: false
---
## Blog 8: Securing Interactions - Authentication in MCP SDKs (OAuth Focus)

**Series:** Deep Dive into the Model Context Protocol SDKs (TypeScript & Python)
**Post:** 8 of 10

In our journey through the Model Context Protocol (MCP) SDKs, we've explored [type definitions](blog-2.md), [server APIs](blog-3.md), [low-level internals](blog-4.md), [client architecture](blog-5.md), and various [transports](blog-6.md) like [Streamable HTTP](blog-7.md). Now, we address a critical aspect of any real-world application integration: **Security and Authentication**.

MCP servers often expose sensitive data (Resources) or powerful capabilities (Tools). Allowing unrestricted access would be a significant security risk. Imagine an AI assistant being able to arbitrarily query your company's internal database or send emails from your account without permission! Authentication ensures that only legitimate, authorized clients can interact with an MCP server, and potentially only with specific permissions.

While various authentication schemes exist, **OAuth 2.1** (the successor to OAuth 2.0) is a strong candidate for standardized authorization in distributed systems like those MCP enables. It allows users to grant specific permissions to client applications without sharing their primary credentials.

This post examines how the TypeScript and Python MCP SDKs approach authentication, with a particular focus on their support (or lack thereof) for built-in OAuth server functionality.

### The Crucial Role of Authentication in MCP

Before diving into specifics, let's establish why authentication is vital:

1.  **Authorization:** It's the foundation for determining *what* a connected client is allowed to do (e.g., call specific tools, read certain resources).
2.  **Identification:** The server needs to know *which* client is making a request, often mapping it back to a specific user or application registration.
3.  **Data Protection:** Prevents unauthorized access to potentially sensitive information exposed via Resources.
4.  **Action Control:** Ensures only permitted clients can trigger Tools that might have side effects or costs.
5.  **Rate Limiting & Auditing:** Identifying clients enables effective rate limiting and logging of actions.

### TypeScript SDK: A "Batteries-Included" OAuth Server

The TypeScript SDK stands out by providing a remarkably comprehensive, built-in solution for implementing an OAuth 2.1 Authorization Server directly within your MCP server application. This functionality resides primarily within the `src/server/auth/` directory.

**Key Components:**

1.  **`mcpAuthRouter` (`src/server/auth/router.ts`):**
    *   This is the central piece – an Express router factory function.
    *   When added to your Express app (typically at the root), it automatically sets up standard OAuth 2.1 endpoints:
        *   `/.well-known/oauth-authorization-server`: Serves the [OAuth Authorization Server Metadata](https://tools.ietf.org/html/rfc8414).
        *   `/authorize`: Handles the user authorization request (often redirecting the user's browser).
        *   `/token`: Handles exchanging authorization codes or refresh tokens for access tokens.
        *   `/register`: (Optional) Handles [Dynamic Client Registration](https://tools.ietf.org/html/rfc7591).
        *   `/revoke`: (Optional) Handles [Token Revocation](https://tools.ietf.org/html/rfc7009).
    *   It takes configuration options, including the crucial `provider`.

2.  **`OAuthServerProvider` (`src/server/auth/provider.ts`):**
    *   An *interface* defining the contract for the actual authorization logic. You need to provide an implementation of this interface to `mcpAuthRouter`.
    *   Methods include `authorize`, `exchangeAuthorizationCode`, `exchangeRefreshToken`, `verifyAccessToken`, `revokeToken`, etc.
    *   This allows plugging in different backend logic (e.g., storing codes/tokens in a database, validating users against an identity provider).

3.  **`ProxyOAuthServerProvider` (`src/server/auth/providers/proxyProvider.ts`):**
    *   A concrete implementation of `OAuthServerProvider` provided by the SDK.
    *   It acts as a *proxy*, forwarding OAuth requests to an *external*, upstream OAuth server (like Auth0, Okta, or your company's SSO).
    *   It simplifies integrating MCP authentication with existing identity infrastructure. You provide the upstream endpoints and implement token verification/client lookup.

4.  **`OAuthRegisteredClientsStore` (`src/server/auth/clients.ts`):**
    *   An interface for managing registered OAuth clients (fetching client details by ID, potentially registering new clients dynamically). You provide an implementation (e.g., backed by a database).

5.  **Handlers (`src/server/auth/handlers/`):**
    *   Internal Express request handlers for each OAuth endpoint (`authorize.ts`, `token.ts`, etc.), used by `mcpAuthRouter`. They parse requests, call the appropriate `OAuthServerProvider` methods, and format responses according to OAuth specs.

6.  **Middleware (`src/server/auth/middleware/`):**
    *   `authenticateClient`: Middleware used by the `/token` and `/revoke` endpoints to validate `client_id` and `client_secret` sent in the request body (using `client_secret_post`).
    *   `requireBearerAuth`: *Crucially*, this middleware is intended to be used on your *actual MCP data/tool endpoints* (e.g., the `/mcp` endpoint for Streamable HTTP). It extracts the `Authorization: Bearer <token>` header, calls `provider.verifyAccessToken` to validate the token, checks expiration and scopes, and attaches the resulting `AuthInfo` to `req.auth` for use in your MCP request handlers.
    *   `allowedMethods`: Utility to enforce HTTP methods.

**Client-Side Helpers (`src/client/auth.ts`):**

The SDK also provides utilities for *clients* to interact with OAuth servers (including those built with the SDK's server components): discovery, starting authorization, exchanging codes, refreshing tokens.

**Summary (TS):** The TypeScript SDK provides a near-complete framework for adding a compliant OAuth 2.1 Authorization Server to your MCP application, either self-contained or proxied. `requireBearerAuth` is the key piece for protecting your MCP Resource/Tool endpoints.

### Python SDK: Leveraging the Ecosystem

In stark contrast to the TypeScript SDK, the Python SDK **does not** currently include a dedicated, built-in OAuth server module comparable to `src/server/auth`. The `src/mcp/shared/auth.py` file defines Pydantic models for OAuth concepts (Metadata, Tokens, Client Info), but there's no equivalent to `mcpAuthRouter` or `OAuthServerProvider`.

**How Would Authentication Work?**

This implies that developers using the Python SDK need to implement authentication largely themselves, likely by integrating with the broader Python web and authentication ecosystem. Common approaches would include:

1.  **Using ASGI Middleware:**
    *   The `FastMCP` server integrates with ASGI frameworks (Starlette, FastAPI). Authentication would typically be handled by middleware placed *before* the MCP routes/application.
    *   Libraries like [`Authlib`](https://authlib.org/), [`FastAPI's Security utilities`](https://fastapi.tiangolo.com/tutorial/security/), or custom middleware could be used.
    *   This middleware would inspect the `Authorization: Bearer <token>` header on incoming requests to the MCP endpoint (e.g., `/sse` and `/messages` for the SSE transport).
    *   It would need to validate the token (potentially by calling an external identity provider's introspection endpoint or validating a JWT locally).
    *   Valid authentication information (`AuthInfo`-like data) could potentially be added to the Starlette request's `scope` dictionary or a custom request extension for access within MCP handlers.

2.  **Implementing OAuth Endpoints Separately:**
    *   If the MCP server *itself* needs to act as the OAuth Authorization Server (issuing tokens), the developer would need to implement the `/authorize`, `/token`, etc., endpoints manually, likely using a library like `Authlib` alongside Starlette/FastAPI. These endpoints would live *alongside* the MCP endpoints (`/sse`, `/messages`).

3.  **Checking Auth within Handlers:**
    *   While less ideal for separation of concerns, authentication *could* potentially be checked within individual `FastMCP` tool/resource handlers using the injected `Context` object. The context might provide access to request headers (depending on the underlying transport and framework integration), allowing manual extraction and validation of the Bearer token. This couples auth logic tightly with business logic.

```python
# Conceptual Python Example (using hypothetical middleware)
from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.middleware.authentication import AuthenticationMiddleware # Example
from starlette.authentication import AuthCredentials, SimpleUser # Example

# --- Hypothetical Auth Backend (using Starlette's patterns) ---
class BearerTokenAuthBackend: # You'd implement this
    async def authenticate(self, conn):
        if "authorization" not in conn.headers:
            return None
        auth = conn.headers["authorization"]
        try:
            scheme, token = auth.split()
            if scheme.lower() != 'bearer':
                return None
            # *** YOUR TOKEN VALIDATION LOGIC HERE ***
            # E.g., call external provider, validate JWT
            # user_info = await validate_my_token(token)
            # if user_info:
            #    return AuthCredentials(["authenticated"]), SimpleUser(user_info['id'])
            if token == "valid-token-for-test": # Replace with real validation
                return AuthCredentials(["authenticated"]), SimpleUser("user123")
        except ValueError:
            pass # Invalid header format
        except Exception as e:
            print(f"Token validation error: {e}") # Log error
        return None # Failed validation

# --- MCP Setup ---
from mcp.server.fastmcp import FastMCP, Context
from mcp.server.sse import SseServerTransport

mcp = FastMCP("MySecureServer")
sse_transport = SseServerTransport("/messages/")

@mcp.tool()
def protected_tool(ctx: Context) -> str:
    # Access authenticated user from middleware (if populated)
    if not ctx.request_context.session.scope.get("user", None).is_authenticated:
         raise PermissionError("Authentication required")
    # user = ctx.request_context.session.scope["user"]
    # print(f"Executing tool for authenticated user: {user.display_name}")
    return "Sensitive data returned"

# --- ASGI App Setup ---
async def handle_sse_get(request):
    async with sse_transport.connect_sse(...) as (r, w):
        await mcp._mcp_server.run(r, w, ...) # Run MCP logic

middleware = [
    Middleware(AuthenticationMiddleware, backend=BearerTokenAuthBackend())
]
app = Starlette(
    routes=[...], # Your MCP routes using handle_sse_get and sse_transport.handle_post_message
    middleware=middleware
)
```

**Summary (Python):** The Python SDK relies on the developer to integrate authentication using standard Python web framework practices (likely ASGI middleware) and external libraries. It provides the Pydantic models for OAuth concepts but not the server-side endpoint implementations or bearer auth middleware.

### Comparison: TS vs. Python Authentication Approach

| Feature                   | TypeScript SDK                             | Python SDK                                     | Notes                                                                                                     |
| :------------------------ | :----------------------------------------- | :--------------------------------------------- | :-------------------------------------------------------------------------------------------------------- |
| **OAuth Server Built-in** | Yes (`mcpAuthRouter`, `OAuthServerProvider`) | No                                             | TS provides a comprehensive framework out-of-the-box.                                                     |
| **Bearer Auth Middleware**| Yes (`requireBearerAuth`)                  | No (Requires custom/external middleware)     | TS explicitly provides middleware for protecting MCP endpoints.                                             |
| **Client Auth Middleware**| Yes (`authenticateClient`)                 | No (Requires custom/external middleware)     | TS provides middleware for validating `client_id`/`secret` at token/revoke endpoints.                     |
| **Flexibility**           | More opinionated (follows OAuth standard)  | High (Integrate any auth system via ASGI)    | Python offers more freedom but requires more manual setup for standard OAuth.                             |
| **Setup Effort (OAuth)**  | Lower (using `mcpAuthRouter`)              | Higher (Requires implementing endpoints/middleware) | Getting a standard OAuth server running is significantly easier with TS SDK.                            |
| **Proxy Support**         | Built-in (`ProxyOAuthServerProvider`)      | Manual Implementation Required                 | TS simplifies integration with existing external OAuth providers.                                       |

### End-User Impact: Security, Trust, and Permissions

Regardless of the SDK implementation details, robust authentication is paramount for the end user:

1.  **Security & Privacy:** Users can trust that their data exposed via MCP Resources is only accessible by applications they have explicitly authorized. Unauthorized actions via Tools are prevented.
2.  **Control & Consent:** OAuth flows allow users to grant specific permissions (scopes) to applications (e.g., "allow Assistant to *read* calendar" vs. "allow Assistant to *read and write* calendar").
3.  **Seamless Experience:** When implemented correctly, the complexities of token management (acquisition, refresh, secure storage) are handled by the client application, providing a seamless experience for the user after the initial authorization grant.
4.  **Accountability:** Authenticated requests allow for proper auditing and logging, tracing actions back to specific clients or users.

### Conclusion

Authentication is a non-negotiable aspect of building secure and trustworthy MCP applications. The TypeScript and Python SDKs present contrasting philosophies: TypeScript offers a comprehensive, integrated OAuth 2.1 server framework, simplifying standard implementations, while Python relies on the developer to leverage the broader ASGI and authentication library ecosystem for greater flexibility but requiring more manual setup.

The TypeScript SDK's `requireBearerAuth` middleware (or an equivalent custom implementation in Python) is the critical component for protecting the actual MCP Tool and Resource interactions once a client has obtained an access token. Properly securing these interactions is essential for building user trust and enabling powerful, context-aware AI integrations safely.

In our next post, we'll explore some of the more **Advanced Capabilities** offered by the SDKs, such as dynamic server updates, context injection, CLI tooling, and resumability. Stay tuned!

---
