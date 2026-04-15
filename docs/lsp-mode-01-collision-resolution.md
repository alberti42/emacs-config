# LSP Protocol Fix: ID Collision and Kind-First Routing

This document outlines a protocol-level bug discovered in `lsp-mode` (Emacs) during the debugging of the `ltex-ls-plus` language server, and the surgical patch implemented to resolve it.

## The Problem: Logic Deadlock

When using an LSP server with high background request volume (like `ltex` with completions enabled) and slow synchronous checks (like the external LanguageTool API), a deadlock can occur where the server enters an infinite "checking" state.

### Root Cause: ID Collision
The JSON-RPC 2.0 protocol allows IDs to be either **Integers** or **Strings**. Many LSP libraries (like `lsp4j` used by `ltex-ls-plus`) use strings for server-initiated requests (e.g., `"1"`, `"2"`) to avoid colliding with the integers (e.g., `1`, `2`) typically used by clients.

In `lsp-mode`, however, the message dispatcher was found to be "kind-blind"—it prioritized matching the `id` field against pending requests without first verifying if the incoming message was a **Response** or a new **Request**.

### Deadlock Sequence (Observed)
1. **Emacs** sends a completion request with **Integer ID `4`**.
2. **Server** sends a `workspace/configuration` request with **String ID `"4"`**.
3. **Emacs** receives the message with ID `4`. Because it has a pending request with ID `4`, the dispatcher "claims" the message as the response to the completion.
4. **Collision:** The server's request is "swallowed" by the client's completion handler.
5. **Deadlock:** The server refuses to finish the document check until it receives the configuration response for ID `"4"`. Emacs is waiting for the server to finish the check. Neither side ever sends another message.

## The JSON-RPC Distinction
As per the specification, message types are unambiguously distinguishable by their structure:

| Message Type | Field: `method` | Field: `result` or `error` | Field: `id` |
| :--- | :--- | :--- | :--- |
| **Request** | Required | MUST NOT be present | Required |
| **Notification**| Required | MUST NOT be present | MUST NOT be present |
| **Response** | MUST NOT be present | Required | Required (matching Request) |

A robust client must route by **Kind** (presence of `method`) before matching by **ID**.

## The Surgical Fix: Kind-First Routing

The patch redefines `lsp--parser-on-message` to implement strict routing.

### Patched Logic
1. Check for the **`method`** field first.
2. If `method` is present:
   - If `id` is also present, it is a **Request**. Dispatch to `lsp--on-request`.
   - If `id` is absent, it is a **Notification**. Dispatch to `lsp--on-notification`.
3. If `method` is absent and `id` is present:
   - It is a **Response** (or Error Response). Match against `lsp--client-response-handlers`.

### Implementation in `lsp-core.el`
The fix is implemented by overriding `lsp--get-message-type` or `lsp--parser-on-message` in the `lsp-mode` initialization block:

```elisp
(defun lsp--parser-on-message (json-data workspace)
  (with-lsp-workspace workspace
    (-let* ((client (lsp--workspace-client workspace))
            ;; 1. Determine type by structure (Kind-First), not just ID presence
            (message-type (cond
                           ((lsp:json-message-method? json-data)
                            (if (lsp:json-message-id? json-data) 'request 'notification))
                           ((lsp:json-message-id? json-data)
                            (if (lsp:json-message-error? json-data) 'response-error 'response))
                           (t 'notification)))
            (id (lsp:json-response-id json-data)))
      (pcase message-type
        ('response
         ;; Only look up handlers if we are certain it's a response
         (-let [(callback ...) (gethash id (lsp--client-response-handlers client))]
           ...))
        ('request (lsp--on-request workspace json-data))
        ...))))
```

## Diagnostic Tools

A Python script has been created to audit LSP logs for ID collisions and congestion:
`docs/parse-ltex-stdin-emacs.py`.

Usage:
```bash
python3 docs/parse-ltex-stdin-emacs.py /tmp/ltex-stdin-emacs.log
```
This script identifies instances where the same numeric ID is used for both an outgoing Request and an outgoing Response, which is a primary indicator of the protocol-level congestion described above.

## Current Status
- **Local Fix:** Applied globally in `lsp-core.el` to protect all LSP clients.
- **Empirical Proof:** Logs (`ltex-stdin-emacs.log`) confirmed that when Integer ID `4` (client completion) and String ID `"4"` (server configuration) were sent simultaneously, the patched dispatcher correctly routed the server request to the configuration handler instead of the completion handler.
- **Upstream:** This logic should be submitted as a PR to `lsp-mode`.
