# Kind-First Patch Bug in `lsp-core.el` (and `lsp-ltex-plus.el`)

## Problem Description

The LTeX+ language server (ltex-ls-plus) was observed to hang in a perpetual checking state, indicated by `isChecking: true` in its status, leading to unresponsiveness within Emacs. This issue was particularly evident when `lsp-completion-enable t` was set, suggesting a potential interaction with high-frequency client requests.

## Initial Investigation & Ruled-Out Hypotheses

An initial hypothesis suggested duplicate ID usage by the LTeX server. However, analysis with `docs/parse-ltex-stdin-emacs.py` on provided log files (`ltex-server-input_example.log`, `ltex-server-output_example.log`) did not reveal any duplicate IDs from the server's perspective, ruling out this theory.

## Observation of the Hang

Further inspection of the LSP communication logs confirmed that the server was indeed stuck. Specifically, `_ltex.getServerStatus` requests consistently showed `isChecking: true`, indicating an ongoing but never-completing check for a particular document.

A key observation was the server sending `window/workDoneProgress/create` requests (e.g., with ID "16"), which went unresponded by Emacs. While Emacs successfully responded to earlier server-initiated requests (e.g., IDs "1" through "15", including other `window/workDoneProgress/create` calls and `workspace/configuration` requests), ID "16" and subsequent progress-related requests were silently ignored.

## The "Kind-First" Patch

Both `lsp-core.el` (where a general patch for `lsp-mode` is applied) and `lsp-ltex-plus.el` (which applies an identical patch if `lsp-ltex-plus-apply-kind-first-patch` is enabled, though it defaults to `nil`) contain a redefinition of the `lsp--parser-on-message` function. This "Kind-First" patch was designed to prevent protocol deadlocks by prioritizing the `method` field over the `id` field when routing incoming JSON-RPC messages from the server. The intention was to correctly distinguish between server-initiated requests/notifications and responses to client requests, especially when IDs might collide.

## The Root Cause: Incorrect ID Extraction

The core of the problem lies in the implementation of the "Kind-First" patch within `lsp--parser-on-message`. Inside this patched function, the `id` field is extracted using `(--when-let (lsp:json-response-id json-data) ...)`.

The critical flaw is that `lsp:json-response-id` is an accessor function specifically designed to extract the ID from a **JSON-RPC *response* message**. However, the `lsp--parser-on-message` function attempts to use this accessor for *all* incoming messages, including **server-initiated *request* messages** (like `window/workDoneProgress/create`).

When `lsp:json-response-id` is called on a server-initiated *request* message (which has its `id` field at the top level of the JSON object, not nested within a `result` or `error` field like a response), it fails to find the ID in the expected "response" structure. This failure likely results in an error being thrown during ID extraction.

This error is then silently caught by the `(with-demoted-errors ...)` block surrounding the message processing. Because the error is demoted and handled, the processing of that specific message (e.g., the `window/workDoneProgress/create` request with ID "16") is prematurely halted, and the message is effectively **silently dropped** without reaching the appropriate request handler (`lsp--on-request`).

## Implications

The silent dropping of `window/workDoneProgress/create` requests means that:

1.  Emacs never acknowledges to the server that it has received the request to initiate a new work progress or check.
2.  The LTeX+ server, waiting for this acknowledgment, remains in an `isChecking: true` state indefinitely. It continues to process other messages (like completion requests or subsequent server status inquiries) but cannot complete the primary checking task because its progress token has not been properly established with the client.

This explains why Emacs appeared to be stuck, even though the server was still sending messages. The "Kind-First" patch, intended to improve robustness, inadvertently introduced a new, silent failure mode by misusing an accessor function for message ID extraction.

## Example Data Reference

*   **Server-initiated request ID "16"**: `{"jsonrpc":"2.0","id":"16","method":"window/workDoneProgress/create", ...}` was observed in `/tmp/ltex-server-output_example.log`.
*   **Lack of Emacs response**: No corresponding response for ID "16" was found in `/tmp/ltex-server-input_example.log`.

## Conclusion

The LTeX+ server hang, characterized by a persistent `isChecking: true` state, is caused by a bug in the "Kind-First" patch applied to `lsp--parser-on-message` in `lsp-core.el` (and potentially `lsp-ltex-plus.el`). This bug leads to the incorrect extraction of `id` from server-initiated request messages, causing these messages to be silently dropped by Emacs. As a result, critical requests like `window/workDoneProgress/create` are never properly handled, leaving the language server in a stalled state.