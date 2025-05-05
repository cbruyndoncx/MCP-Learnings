Okay, here is a detailed draft for Blog Post 6 in the *new* advanced series structure (original Blog 10 plan, post #6), focusing on the Prompt primitive across the four SDKs.

---

## Blog 6: Guiding Interactions - The Prompt Primitive Across MCP SDKs

**Series:** Deep Dive into the Model Context Protocol SDKs (Advanced Topics)
**Post:** 6 of 12

In our ongoing deep dive into the Model Context Protocol (MCP) SDKs, we've analyzed the core protocol ([Blog 2](link-to-post-2)), server architecture ([Blog 3](link-to-post-3), [Blog 4](link-to-post-4)), client APIs ([Blog 5](link-to-post-5)), and the action-oriented [Tool primitive](link-to-post-11). Now, we examine another crucial server feature: **Prompts**.

While Tools allow AI models to *act*, Prompts provide predefined templates and workflows designed primarily for **user control**. They act as standardized starting points for common interactions, often surfaced in client UIs as slash commands, buttons, or menu items. Unlike Resources (application-controlled data) or Tools (model-controlled actions), Prompts guide the *initiation* of a specific task or conversation flow, potentially involving arguments supplied by the user.

This post targets advanced developers, comparing how the [MCP Prompt specification](https://modelcontextprotocol.io/specification/draft/server/prompts) is implemented across the TypeScript, Python, C#, and Java SDKs. We'll explore:

1.  **Prompt Definition:** Metadata (`name`, `description`) and Argument (`arguments`) specification.
2.  **Registration:** How prompt logic is registered (Methods, Decorators, Attributes, Specifications).
3.  **Argument Handling:** Schema definition, validation, and binding to handler parameters.
4.  **Message Generation:** Handler return types and conversion to `PromptMessage` lists containing various `Content` types (including `EmbeddedResource`).
5.  **Discovery & Retrieval:** The `prompts/list` and `prompts/get` flow.
6.  **Advanced Features:** Argument completion (where available).

### The Prompt Specification: Templated Interactions

The MCP specification defines a `Prompt` metadata object and a `prompts/get` request/response flow.

*   **`Prompt` Metadata:** Advertised via `prompts/list`, includes:
    *   `name`: Unique identifier.
    *   `description`: For UI/LLM understanding.
    *   `arguments` (Optional): A list of `PromptArgument` objects (`name`, `description`, `required`) defining parameters the prompt accepts.
*   **`prompts/get` Request:** Client requests a prompt by `name`, providing user-supplied `arguments` as a string dictionary.
*   **`GetPromptResult` Response:** Server returns:
    *   `description` (Optional).
    *   `messages`: A list of `PromptMessage` objects (`role`, `content`).
*   **`PromptMessage.content`:** Can be `TextContent`, `ImageContent`, `AudioContent`, or `EmbeddedResource`.

The core idea is that the client fetches the prompt structure (often based on user action), providing arguments, and the server returns the initial set of messages to kick off the interaction with the LLM.

### SDK Implementations: Defining and Handling Prompts

**1. TypeScript (`McpServer.prompt()`): Explicit Schemas, Structured Results**

*   **Definition:** Uses `mcpServer.prompt()` method. Takes `name`, optional `description`, an optional explicit Zod object schema (`argsSchema`) for arguments, and the handler callback.
*   **Argument Schema:** Defined using Zod (`z.object({...})`). `Completable` wrapper (`completable(z.string(), ...)`) can be used for arguments needing autocompletion.
*   **Handler:** An async function receiving a type-safe `args` object (inferred from Zod schema) and the `RequestHandlerExtra` context.
*   **Validation:** Zod schema validation performed automatically by `McpServer` before calling the handler.
*   **Result Handling:** Handler *must* return `Promise<GetPromptResult>`, explicitly constructing the `{ messages: [...] }` structure containing `PromptMessage` objects. No automatic conversion from simpler types.
*   **Discovery/Retrieval:** `McpServer` automatically handles `prompts/list` (generating `PromptArgument` metadata from Zod schema) and `prompts/get` (finding handler, validating args, calling handler).

```typescript
// TypeScript Prompt Definition
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { completable } from "@modelcontextprotocol/sdk/server/completable.js";
import { GetPromptResult, PromptMessage } from "@modelcontextprotocol/sdk/types.js";

const mcpServer = new McpServer(/* ... */);

const reviewArgsSchema = z.object({
  filePath: completable(z.string(), async (partial) => findFiles(partial)) // Autocomplete file paths
              .describe("Path to the code file"),
  focusArea: z.enum(["performance", "security", "style"]).optional()
});

mcpServer.prompt<typeof reviewArgsSchema>(
  "review_code_ts",
  "Generate prompt for code review",
  reviewArgsSchema, // Explicit Zod schema
  async (args, extra): Promise<GetPromptResult> => {
    const fileContent = await readFileContent(args.filePath); // Assume helper function
    const messages: PromptMessage[] = [
      { role: "user", content: { type: "text", text: `Review this file: ${args.filePath}` } },
      {
        role: "user",
        content: {
          type: "resource", // Embed the file content
          resource: { uri: `file://${args.filePath}`, text: fileContent, mimeType: 'text/plain' }
        }
      }
    ];
    if (args.focusArea) {
      messages.push({ role: "user", content: { type: "text", text: `Focus on ${args.focusArea}.` } });
    }
    return { description: "Code review prompt", messages }; // Explicit GetPromptResult
  }
);
```

**2. Python (`@mcp.prompt()`): Decorators, Flexible Returns**

*   **Definition:** Uses `@mcp.prompt()` decorator on a function. `name` defaults to function name, `description` to docstring.
*   **Argument Schema:** Inferred from function parameter type hints (using Pydantic). `Field` or `Annotated` add metadata.
*   **Handler:** The decorated function. Receives validated arguments. Optional `Context` injection.
*   **Validation:** Automatic via Pydantic model derived from signature.
*   **Result Handling:** **Highly flexible.** Handler can return:
    *   `str` (-> single `UserMessage` with `TextContent`)
    *   `mcp.server.fastmcp.prompts.base.Message` (User/Assistant)
    *   `dict` (parsed as `Message`)
    *   `Sequence` of the above.
    `FastMCP` automatically converts these into the required `GetPromptResult` containing `PromptMessage`s.
*   **Discovery/Retrieval:** `FastMCP` automatically handles `prompts/list` (deriving arguments from signature) and `prompts/get`.

```python
# Python Prompt Definition
from mcp.server.fastmcp import FastMCP
from mcp.server.fastmcp.prompts.base import UserMessage, AssistantMessage, EmbeddedResource, TextResourceContents
from typing import Annotated
from pydantic import Field, FilePath

mcp = FastMCP("PyServer")

@mcp.prompt()
async def review_code_py(
    file_path: Annotated[FilePath, Field(description="Path to code file")], # Use FilePath type
    focus_area: Annotated[str | None, Field(description="Area to focus on")] = None
) -> list[Message]: # Return list of Message objects
    """Generates a code review prompt (docstring description)."""
    # file_content = await read_file_async(file_path) # Assume helper
    file_content = "def hello(): pass"
    messages = [
        UserMessage(f"Review this file: {file_path}"),
        UserMessage(EmbeddedResource(type="resource", resource=TextResourceContents(
            uri=f"file://{file_path}", text=file_content, mimeType='text/plain'
        )))
    ]
    if focus_area:
        messages.append(UserMessage(f"Focus on {focus_area}."))
    messages.append(AssistantMessage("Understood. Analyzing the code now..."))
    return messages # SDK converts this list to GetPromptResult
```

**3. C# (`[McpServerPrompt]`): Attributes, DI, Various Return Types**

*   **Definition:** Uses `[McpServerPrompt]` attribute on methods within `[McpServerPromptType]` classes. `Name` and `Description` from attributes or reflection.
*   **Argument Schema:** Inferred using `AIFunctionFactory` from method parameters (excluding DI/context params). `[Description]` attribute used for parameter descriptions.
*   **Handler:** The attributed method. Can receive dependencies via DI.
*   **Validation:** Automatic via `AIFunction` invocation mechanism.
*   **Result Handling:** Flexible. Handler can return `GetPromptResult`, `string`, `PromptMessage`, `IEnumerable<PromptMessage>`, `ChatMessage`, or `IEnumerable<ChatMessage>`. The `AIFunctionMcpServerPrompt` wrapper converts these to the final `GetPromptResult`.
*   **Discovery/Retrieval:** Handled automatically by the configured `McpServer` based on registered `McpServerPrompt` instances (often discovered via DI extensions like `WithPromptsFromAssembly`).

```csharp
// C# Prompt Definition
using ModelContextProtocol.Server;
using System.ComponentModel;
using Microsoft.Extensions.AI; // For ChatMessage
using ModelContextProtocol.Protocol.Types; // For PromptMessage, Content etc.

[McpServerPromptType]
public class ReviewPrompts(IFileSystemService fileService) // Constructor DI
{
    [McpServerPrompt(Name = "review_code_cs")]
    [Description("Generates a code review prompt")]
    public async Task<List<ChatMessage>> GenerateReviewPrompt( // Returns ChatMessage list
        RequestContext<GetPromptRequestParams> context, // MCP Context
        [Description("Path to the code file")] string filePath,
        [Description("Optional focus area")] string? focusArea = null)
    {
        var fileContent = await fileService.ReadFileAsync(filePath, context.RequestAborted);
        var messages = new List<ChatMessage>
        {
            new(ChatRole.User, $"Review this file: {filePath}"),
            new(ChatRole.User, new TextContent(fileContent)) // Simple text embedding
            // Could also construct PromptMessage with EmbeddedResource for richer context
        };
        if (!string.IsNullOrEmpty(focusArea))
        {
            messages.Add(new(ChatRole.User, $"Focus on {focusArea}."));
        }
        return messages; // SDK wrapper converts to GetPromptResult
    }
}
```

**4. Java (`PromptSpecification`): Explicit Specs, Structured Results**

*   **Definition:** Requires creating a `Prompt` record (metadata including manually defined `List<PromptArgument>`) and pairing it with a handler `BiFunction` in an `Async/SyncPromptSpecification`, passed to the `McpServer` builder.
*   **Argument Schema:** Manually defined when creating the `Prompt` metadata record.
*   **Handler:** A `BiFunction` taking `McpAsync/SyncServerExchange` and `GetPromptRequest`, returning `GetPromptResult` (Sync) or `Mono<GetPromptResult>` (Async).
*   **Validation:** Responsibility of the handler function to validate arguments from the `GetPromptRequest.arguments()` map against the defined schema.
*   **Result Handling:** Handler *must* explicitly construct and return the `GetPromptResult` object containing `PromptMessage`s.
*   **Discovery/Retrieval:** Handled by the core `McpServerSession` using registered `listPromptsHandler` and `getPromptHandler` (which were populated by the builder based on the provided specifications).

```java
// Java Prompt Definition
import io.modelcontextprotocol.server.*;
import io.modelcontextprotocol.spec.McpSchema.*;
import reactor.core.publisher.Mono;
import java.util.List;
import java.util.Map;

Prompt reviewPromptMeta = new Prompt(
    "review_code_java",
    "Generates review prompt",
    List.of(
        new PromptArgument("filePath", "Path to file", true),
        new PromptArgument("focusArea", "Focus area", false)
    )
);

// Async Handler Function
BiFunction<McpAsyncServerExchange, GetPromptRequest, Mono<GetPromptResult>> asyncHandler =
    (exchange, req) -> Mono.defer(() -> {
        // Manual Argument Validation Needed Here!
        Map<String, String> args = req.arguments() != null ? req.arguments() : Map.of();
        String filePath = args.get("filePath");
        if (filePath == null) {
            return Mono.error(new McpError("Missing required argument: filePath"));
        }
        String focusArea = args.get("focusArea");
        // String fileContent = readFileAsync(filePath); // Assume helper

        List<PromptMessage> messages = new ArrayList<>();
        messages.add(new PromptMessage(Role.USER, new TextContent("Review: " + filePath)));
        // messages.add(new PromptMessage(Role.USER, new EmbeddedResource(...)));
        if (focusArea != null) {
            messages.add(new PromptMessage(Role.USER, new TextContent("Focus: " + focusArea)));
        }

        return Mono.just(new GetPromptResult("Code review prompt", messages)); // Explicit result
    });

AsyncPromptSpecification reviewSpec = new AsyncPromptSpecification(reviewPromptMeta, asyncHandler);

// Register with builder
McpServer.async(provider).prompts(reviewSpec).build();
```

### Synthesis: Defining and Using Prompts

| Feature            | TypeScript                      | Python (`FastMCP`)                 | C#                                  | Java                                     |
| :----------------- | :------------------------------ | :--------------------------------- | :---------------------------------- | :--------------------------------------- |
| **Definition**     | `McpServer.prompt()`            | `@mcp.prompt()` decorator          | `[McpServerPrompt]` attribute         | `PromptSpecification` + Builder          |
| **Arg Schema**     | Explicit Zod                    | Inferred from Type Hints           | Inferred from Method Signature        | Manual `List<PromptArgument>`            |
| **Arg Validation** | **Automatic (Zod)**             | **Automatic (Pydantic)**           | **Automatic (AIFunction)**          | Manual (in Handler)                      |
| **Handler Context**| `RequestHandlerExtra`           | `Context` (Injected)               | DI Params + `RequestContext`        | `Exchange` object                          |
| **Return Type**    | `Promise<GetPromptResult>`        | **Flexible** (str, Msg, list...)   | Flexible (str, Msg, list...)        | `GetPromptResult`/`Mono<GetPromptResult>`|
| **Result Convert** | Manual                          | **Automatic**                      | Automatic                           | Manual                                   |
| **Arg Completion** | **Yes (`Completable`)**           | No                                 | No                                  | No                                       |
| **Discovery**      | Automatic (`prompts/list`)      | Automatic (`prompts/list`)       | Automatic (`prompts/list`)          | Via `listPromptsHandler` spec            |
| **Retrieval**      | Automatic (`prompts/get`)       | Automatic (`prompts/get`)        | Automatic (`prompts/get`)           | Via `getPromptHandler` spec              |

**Key Observations:**

*   **Ergonomics:** Python's `FastMCP` offers the most concise definition and flexible return types. C#'s attribute-based approach with DI is also quite clean. TypeScript requires explicit schemas and result construction. Java is the most verbose, requiring manual metadata and result construction.
*   **Validation:** TS, Python, and C# provide automatic argument validation based on the schema/signature, reducing boilerplate in the handler. Java handlers must perform validation manually.
*   **Content Flexibility:** All SDKs support `TextContent`, `ImageContent`, `AudioContent` (except Python currently?), and `EmbeddedResource` within the `PromptMessage.content`. Embedding resources is powerful for providing rich context directly within the prompt flow.
*   **Autocompletion:** Only the TypeScript SDK has built-in support for providing completion suggestions for prompt arguments.

### Advanced Use Cases & Nuances

*   **Embedding Resources:** All SDKs allow returning `PromptMessage`s with `EmbeddedResource` content. This is powerful for including file content, database results, or other server-managed data directly in the prompt sent to the LLM, without the client needing to perform a separate `resources/read`. The server handler constructs the `Text/BlobResourceContents` object.
*   **Multi-Turn Prompts:** Handlers can return multiple `PromptMessage` objects, including alternating `user` and `assistant` roles, to set up a specific conversational flow or provide few-shot examples.
*   **Dynamic Prompt Generation:** Since the handler logic runs on `prompts/get`, servers can dynamically generate prompt content based on arguments, current application state, or external data sources.
*   **Contextual Prompts:** Prompt handlers can access session or lifespan context (via `Extra`, `Context`, DI, `Exchange`) to tailor prompts based on the specific user or session state.

### Conclusion: Structuring User-Initiated AI Interactions

Prompts are the MCP primitive for user-controlled interaction templates. They bridge the gap between specific user commands (like slash commands) and structured input for LLMs.

*   **Python (`FastMCP`)** provides the most developer-friendly experience for defining prompts due to its decorators, type inference, and flexible return types.
*   **C#** offers a strong, type-safe alternative closely tied to the .NET DI ecosystem and attributes.
*   **TypeScript** requires more explicit schema definition (Zod) and result construction but benefits from built-in argument autocompletion.
*   **Java** is the most explicit, requiring manual definition of metadata and arguments, handler validation, and result construction, but offers clear separation and framework adapters.

Choosing the right SDK depends on the preferred level of abstraction and integration needs. Regardless of the SDK, well-designed Prompts, potentially incorporating `EmbeddedResource`s, are key to creating intuitive and powerful user-driven workflows powered by MCP and LLMs.

---