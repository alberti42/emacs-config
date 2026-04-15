#+#+#+#+-----------------------------------------------------------------------
# lsp-mode hang: dropped `window/workDoneProgress/create` when a batch aborts

This note documents a reproducible hang observed with `ltex-ls-plus` + `lsp-mode`
when LSP completion is enabled.

The key point: `lsp-mode` can receive multiple JSON-RPC messages in a *single*
process filter invocation, parse them successfully, and then abort dispatch
mid-batch due to a nonlocal exit triggered by an earlier callback. If the
un-dispatched message is a server-initiated request that requires a reply (e.g.
`window/workDoneProgress/create`), the server can wait forever and report a
stuck “checking” state.

## Symptoms

- LTEX+ status remains `isChecking=true` indefinitely.
- LSP wire logs show an unresponded server request:

  - Method: `window/workDoneProgress/create`
  - ID: varies per run (often a string, e.g. `"18"`)

## Ground-truth evidence (wire logs)

The server sends (server -> Emacs):

```json
{"jsonrpc":"2.0","id":"18","method":"window/workDoneProgress/create", ...}
```

but Emacs never sends back the required response (Emacs -> server):

```json
{"jsonrpc":"2.0","id":"18","result":null}
```

LTEX uses this request as part of its work-done progress protocol; without the
reply, its progress machinery can remain in a “checking” state.

## Root cause (what actually goes wrong)

1. The process filter receives a chunk that contains *two* messages:
   - a **server response** (e.g. completion result for the client's numeric id)
   - a **server request** `window/workDoneProgress/create` (with a string id)

2. The filter parses both JSON objects successfully.

3. Dispatch begins. If the response is handled first, its callback can trigger a
   nonlocal exit that aborts the filter’s dispatch loop.

   - `condition-case` will catch `error` and (optionally) `quit`.
   - However, Emacs allows nonlocal exits via `throw` to an active `catch` tag.
     Those do *not* get caught by `condition-case` and will unwind the stack.

4. The remaining messages in that batch never reach `lsp--parser-on-message`, so
   `lsp--on-request` is never called for `window/workDoneProgress/create`, so
   `lsp--send-request-response` never sends the required `result: null` response.

## Why string ids are not the root issue

Server-initiated JSON-RPC requests may use string ids. `lsp-mode` can and does
successfully handle such requests in general.

The problematic scenario is not “id is a string”, but “a server request that
needs an immediate reply is in the same dispatch batch as a callback that can
abort dispatch”.

## Fix direction (for upstream)

The minimal, robust strategy is to ensure server-initiated messages are handled
before any client-response callbacks that might abort dispatch.

Practical options:

1. **Dispatch ordering**: when a filter invocation produces a batch of messages,
   dispatch all messages with a `method` field first (requests + notifications),
   then dispatch responses.

2. **Targeted pre-ACK**: special-case `window/workDoneProgress/create` to reply
   immediately once parsed (reply is always `null`), before any other dispatch.

Option (1) is general and simple; option (2) is narrower but also safe.

## Notes for a PR

- Include wire logs demonstrating: request is present on the wire but response
  is missing.
- Include an explanation of Emacs nonlocal exits (`quit`/`throw`) in process
  filters.
- Redact secrets from logs (e.g. LanguageTool API keys) before posting.
