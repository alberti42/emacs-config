# buffers-config.el

General hub for buffer interaction — anything that shapes how the user
lists, navigates, or manages the lifecycle of buffers. New buffer-related
behaviours should land here rather than in standalone modules.

Currently contains:

1. `ibuffer` setup with project-aware grouping and nerd-icons.
2. Smart kill-buffer behavior (suppresses prompt when buffer content
   matches disk).

## External packages

- `ibuffer-project` — generates per-project filter groups from
  `project.el`.
- `nerd-icons-ibuffer` — column icons.

Built-in (`:straight nil`): `ibuffer`.

## Cross-module touchpoints

- **`nerd-icons-config.el`** — same icon font as dired and treemacs;
  no second icon system.
- **`project.el`** — grouping uses whatever `project.el` reports as the
  current root for each buffer. Buffers in repos with submodules respect
  `project-config.el`'s `project-vc-merge-submodules nil`.

## Behavior

### `ibuffer` replaces `list-buffers`

Via `[remap list-buffers]`, so `C-x C-b` opens ibuffer. Configuration:

| Setting                              | Value             | Note |
| ------------------------------------ | ----------------- | ---- |
| `ibuffer-expert`                     | `t`               | no confirmation prompts on common operations |
| `ibuffer-show-empty-filter-groups`   | `nil`             | hide empty project groups |
| `ibuffer-default-sorting-mode`       | `'recency`        | default sort when project-grouping is off |
| `ibuffer-project-use-cache`          | `t`               | cache project lookups for speed |

### Project grouping refreshes on every invocation

`buffers-config--apply-project-groups` is hooked on `ibuffer-hook` (not
`ibuffer-mode-hook`). Every `M-x ibuffer` re-runs the function, so:

- New projects opened since last invocation appear in the listing.
- Filter groups always reflect the current project topology.

### Sort is `project-file-relative` by default but respects user override

The hook only sorts by `project-file-relative` when the current sort mode
isn't already that. So if you manually sort by recency or alphabetically
inside ibuffer, the next refresh keeps your choice — only the *initial*
sort is project-relative. This is intentional UX.

### Smart kill-buffer: skip prompt when content matches disk

`my/maybe-unmark-modified` is hooked on `kill-buffer-query-functions` and
runs *before* the "Buffer modified; kill anyway?" prompt would fire. If
the buffer is flagged modified but the decoded text equals the file on
disk (typical after edits made and fully undone), it clears the modified
flag — Emacs then sees a clean buffer and skips the prompt.

The function returns `t` unconditionally — it never blocks the kill, only
clears the flag where appropriate.

## Invariants — do not change without reading

### `ibuffer-hook`, NOT `ibuffer-mode-hook`

`ibuffer-hook` fires on every `M-x ibuffer` invocation; `ibuffer-mode-hook`
fires only when entering ibuffer-mode the first time. We need the former
because filter groups must regenerate as projects come and go.

If you ever switch this to `ibuffer-mode-hook`, new projects opened after
the first ibuffer invocation will not show up in the listing until you
kill the `*Ibuffer*` buffer — silent breakage.

### `my/maybe-unmark-modified` cost: only paid when buffer is modified

The function reads the file from disk to compare contents, but the read
is gated by `(buffer-modified-p)` — for unmodified buffers, the function
short-circuits and is essentially free. The full disk read only happens
in the rare case where a kill was attempted on a modified buffer.

Don't add additional caching here; the `buffer-modified-p` guard is
already the right gate.

### `buffer-substring-no-properties`, not raw bytes

The comparison uses decoded text (post-coding-system, post-EOL
normalization). This is correct: a file with CRLF line endings decoded
to LF in the buffer should still compare equal. Don't switch to byte-level
comparison or `md5` of raw file contents — it would produce false
"buffer differs from disk" results on Windows-style line endings or
non-UTF8 encodings.
