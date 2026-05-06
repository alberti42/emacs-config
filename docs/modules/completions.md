# completions/ — styles, orderless, cape (dict CAPF)

Three closely-coupled modules. Together they decide *which* completion
style runs for *which* category, and provide an in-memory English-word
CAPF for prose buffers. Documented together because each piece only
makes sense in the context of the other two.

## Files

- `completions/styles.el` — baseline `completion-styles`,
  `completion-category-overrides`, and the `completion--styles` advice
  that changes how the two interact.
- `completions/orderless.el` — Orderless package and per-category
  overrides (`file`, `emacs-config-dict`).
- `completions/cape.el` — Cape sources, `emacs-config-cape-dict-prefix`,
  and the `yasnippet-capf` wiring.

## The keystone: overrides replace, not prepend

Stock Emacs (`completion--styles` in `minibuffer.el`):

```elisp
(if over
    (delete-dups (append (cdr over) (copy-sequence completion-styles)))
   completion-styles)
```

A category override styles list is **prepended** to the global
`completion-styles`, not used in isolation. With global
`(orderless basic)` and override `(basic)`, the effective list becomes
`(basic orderless)` — orderless still runs as a fallback whenever
`basic` returns no candidates.

That is surprising and silently re-introduces orderless on every
category override. We treat an explicit per-category override as
authoritative. `styles.el` installs:

```elisp
(define-advice completion--styles
    (:around (orig metadata) override-replaces)
  (let* ((cat (completion-metadata-get metadata 'category))
         (over (completion-category-get cat 'styles)))
    (if over (cdr over) (funcall orig metadata))))
```

After this advice, `(file (styles basic partial-completion))` really
means *only* `(basic partial-completion)`. `(emacs-config-dict (styles
basic))` really means *only* `(basic)`.

**Consequence**: any third-party package that registered a category
override expecting orderless to remain as a safety net will start
behaving differently. There are none in this config today; if you add
one, audit its override list.

## The dict CAPF

`emacs-config-cape-dict-prefix` (in `cape.el`) is an in-memory English-word
CAPF for prose buffers (Markdown, Org, plain text, LaTeX — see the
respective `syntaxes/*.el`). Fires after 3 typed characters. Reads
`cape-dict-file` once into `emacs-config--dict-words` (~1 MB resident),
filters by prefix in elisp via `completion-table-with-cache`. Tags
results with `:category 'emacs-config-dict`.

### Why not upstream `cape-dict`?

`cape-dict` shells out to `grep -F -m<cape-dict-limit> PREFIX DICT` per
cache miss. Two interacting flaws:

1. **`-F` does substring matching.** `pro` matches `apron`, `appropriate`,
   `approach`, …
2. **`-m100` caps results.** The dictionary is alphabetically sorted, so
   the cap is exhausted by earlier-alphabet substring matches before
   any actual `pro*` word is reached.

Combine those with the appending-styles bug above and the `basic` style
returns nothing (no candidates start with `pro`), orderless takes over
as a fallback, and the popup fills with `apron`-style noise — exactly
what the user *didn't* type.

The in-memory CAPF sidesteps all three issues at once: prefix-only by
construction, no result cap, no subprocess. With the styles advice in
place, orderless never runs for the dict category anyway.

### Performance

- Dictionary read: one-shot, on first prose completion, ~10–30 ms.
- Per-keystroke filter: `seq-filter` over ~250k words plus
  `completion-table-with-cache` memoization. Sub-millisecond after the
  first invocation per prefix.

## Invariants — do not change without reading

### `:category 'emacs-config-dict` must stay on the CAPF result

The category is what hooks the CAPF into the
`(emacs-config-dict (styles basic))` override and (via the styles
advice) into the orderless-skip behavior. Strip it and orderless
quietly reappears in the styles list, undoing the optimization without
any visible breakage in the candidate list.

### Order of loading: styles → orderless → cape

`completion.el` loads in this order. The advice in `styles.el` must be
in place before any code path can call `completion--styles`. The
`emacs-config-dict` override in `orderless.el`'s `:custom` block must
be in place before any prose buffer fires the dict CAPF. Don't
reorder.

### Don't re-add `cape-dict-3`

Earlier versions of the prose-mode hooks used `cape-dict-3` (a
`cape-capf-prefix-length` wrapper around upstream `cape-dict`).
Removed deliberately. The four prose syntax files
(`syntaxes/markdown.el`, `org.el`, `text.el`, `latex.el`) all hook
`emacs-config-cape-dict-prefix` instead.

### `emacs-config--dict-words` is intentionally global, not per-buffer

The cache is global state because the dictionary file is global state
— there's only one `cape-dict-file`. If a future per-language
dictionary requirement appears, the cache shape will need to change
(keyed by file path or language).

## yasnippet-capf

Snippet keys appear as completion candidates via `yasnippet-capf`,
which walks `yas--get-snippet-tables` for the current buffer
(respecting `major-mode`, parent modes, and any
`yas-activate-extra-mode` bridges configured in
`yasnippet-config.el`). Selection triggers `yas-expand-snippet`.

The CAPF actually registered everywhere is
`emacs-config-yasnippet-capf`, defined in `cape.el`. It wraps the bare
`yasnippet-capf` with two adjustments:

1. **`cape-capf-prefix-length` gate at 3 chars.** Snippet keys are
   practically always ≥3 chars; gating skips snippet-key noise on 1–2
   char input where the much larger LSP candidate list dominates
   anyway.
2. **Literal-prefix candidate filter via `:predicate`.** The bare CAPF
   returns *every* snippet for the active mode and lets completion
   styles do the filtering. Combined with orderless's substring
   semantics, that surfaces every snippet whose key contains the
   typed character anywhere — distracting. The predicate restricts
   the candidate set to snippets whose key *starts with* the typed
   prefix, regardless of the active completion style.

The predicate-based filter is what makes the prefix-only behaviour
hold inside `cape-capf-super` too: `cape-capf-super` overwrites the
inner CAPF's `:category` with its own (`cape-super`), so a per-category
style override like `(yasnippet (styles basic))` would only kick in for
the standalone use, not inside the merged super. Predicates flow
through the super untouched, so prefix-only filtering applies in both
LSP and non-LSP buffers.

**In LSP buffers**, `lsp-core.el`'s `lsp-completion-mode-hook` replaces
the bare `lsp-completion-at-point` entry with a `cape-capf-super` that
merges `emacs-config-yasnippet-capf` and LSP into one popup, with
snippets ranked first. The super is wrapped in
`cape-capf-properties :exclusive 'no` so the chain still falls through
to `cape-file` / `cape-tex` when neither inner CAPF matches.

The standalone `emacs-config-yasnippet-capf` entry remains in the
global chain — redundant but harmless inside LSP buffers (the super
already covers it), and the active snippet source in non-LSP buffers.

## Prose super-CAPF: dabbrev + dict

Prose buffers (Markdown, Org, plain text, LaTeX) hook
`emacs-config-cape-prose` instead of the bare dict CAPF. It is a
`cape-capf-super` of `(cape-capf-prefix-length #'cape-dabbrev 3)` and
`emacs-config-cape-dict-prefix`, wrapped with
`cape-capf-properties :exclusive 'no`.

Why merge:

- Both inner CAPFs use word bounds — bounds match, super-CAPF safe.
- Their candidate sets are complementary: dabbrev surfaces
  buffer-recent words (project-specific names, jargon, identifiers
  from a code window), dict surfaces the English dictionary. They
  almost never overlap.
- In a flat chain, the dict CAPF returns a non-empty result for
  almost every 3+ char prefix (≈250k English words → there's always
  a match), so `:exclusive 'no` fall-through never happens and
  `cape-dabbrev` is effectively dormant in prose. The merge fixes
  that by ranking both sources side-by-side.

Order: dabbrev first → buffer-recent words appear above dictionary
words (most relevant first).

The standalone global `cape-dabbrev` entry stays — it's the
word-completion source for code buffers, where the dict CAPF is not
hooked.
