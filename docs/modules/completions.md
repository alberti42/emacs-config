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
- `completions/cape.el` — Cape sources plus `emacs-config-cape-dict-prefix`.

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
