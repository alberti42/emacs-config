# Draft: link destinations are used verbatim, never unbracketed or percent-decoded

Covers items 1 and 2 of `00-upstream-candidates (unfiled).md`. Files here: `01-link-destination-repro.el` (reproducer, runs against shipped and patched builds) and `01-link-destination.diff` (the patch, against `origin/master` `ab1d6868ed3`).

Prose below is deliberately unwrapped, one line per paragraph, so it can be pasted into a GitHub issue without hard-wrap artifacts.

---

## Title

`markdown-ts-mode`: link destinations in `<...>` are not recognised (a bracketed URL is opened with `find-file`)

## Body

### Summary

CommonMark lets a link destination be wrapped in pointy brackets, and *requires* that wrapping when the destination contains spaces ([spec 0.31.2, section 6.3 "Links"](https://spec.commonmark.org/0.31.2/#links)). `markdown-ts-mode` never removes the wrapper, so the brackets are carried into the destination everywhere it is used. Two consequences follow, the second one easy to miss:

- `[a](<my file.md>)` — the only spec-legal way to link a file whose name has a space — is passed to `find-file` as the literal string `<my file.md>`, which creates a new empty buffer named `<my file.md>` instead of opening the existing file.
- `[a](<https://example.com/x?a=1&b=2>)` is passed to **`find-file`** rather than `browse-url`. The scheme test in `markdown-ts--make-link-button` is `(string-match-p "\`[a-z]+:" url)`, and with the brackets still attached the string starts with `<`, so a perfectly ordinary bracketed URL is treated as a relative file name.

The same raw node text is used by `markdown-ts--fontify-image`, which resolves it with a bare `expand-file-name`, so `![a](<my pic.png>)` fails the `file-exists-p` guard and the image silently never renders.

Separately and more mildly, a percent-encoded destination (`[a](my%20file.md)`) is not decoded either, so it does not reach `my file.md`. This half is a convenience rather than a conformance issue and has a trade-off — see "On percent-decoding" below — so it may be worth applying only the bracket half.

### Why it matters

A file name with a space has no other spelling. Percent-encoding it is not portable across Markdown tools, and leaving the space bare makes it not a link at all (the grammar does not parse `[a](my file.md)` as an inline link, correctly). So `<...>` is the spelling, and it currently does not work — the one thing a user with spaces in file names must write is the one thing that fails.

The bracketed-URL case is worse than a non-working link, because `find-file` on a URL-shaped string is not a no-op: it opens a buffer visiting a nonsense relative path, and a subsequent save would create it.

### Recipe

Reproducer attached (`01-link-destination-repro.el`); it stubs `find-file` and `browse-url`, so nothing is opened or browsed. `emacs -Q --batch -l 01-link-destination-repro.el` against the current build prints:

```
 #  destination as written             handed to                  ok?
 -- ---------------------------------- -------------------------- ---
 1  <my target.md>                     find-file "<my target.md>" FAIL   bracketed name with a space
 2  my%20target.md                     find-file "my%20target.md" FAIL   percent-encoded name with a space
 3  plain.md                           find-file "plain.md"       PASS   control: plain relative name
 4  <https://ex.com/x?a=1&b=2>         find-file "<https://ex.com/x?a=1&b=2>" FAIL   bracketed URL
 5  https://ex.com/q?s=a%20b           browse-url "https://ex.com/q?s=a%20b" PASS   control: URL with a %20 escape
 6  <50% off.md>                       find-file "<50% off.md>"   FAIL   bracketed name with a literal %
 7  <100%25 done.md>                   find-file "<100%25 done.md>" FAIL   bracketed name literally containing %25
```

By hand: create a file called `my target.md`, put `[a](<my target.md>)` in a sibling `.md` buffer, and press `RET` on the label. Expected: the file opens. Actual: an empty buffer named `<my target.md>`.

### Suggested fix

Attached as `01-link-destination.diff` (against `ab1d6868ed3`). Two small helpers plus three call-site changes:

- `markdown-ts--unbracket-destination` strips a matched `<...>` pair.
- `markdown-ts--destination-file-name` strips the wrapper and then percent-decodes, but *only* when the string actually contains a `%XX` escape, so a literal `%` in a file name is left alone.
- `markdown-ts--make-link-button` unbrackets **once at the top**, before the cond. This is what fixes the bracketed-URL case, since the scheme test then sees `https:`, and it also makes `help-echo` show the destination rather than its delimiters. Only the final (local file) branch percent-decodes; a URL keeps its escapes untouched.
- `markdown-ts--fontify-image` unbrackets at extraction, so the `https?://` remote test is also correct for a bracketed remote image, and percent-decodes only in the local-file branch.

Unbracketing inside `markdown-ts--make-link-button` rather than at each extraction site means reference links and autolinks are covered by the same change, since they all build their button through it.

With the patch, the same reproducer prints `PASS` for cases 1–6.

### On percent-decoding

Case 7 in the reproducer still fails with the patch, and that is inherent rather than a flaw in it: a file whose name literally contains `%25` cannot be distinguished from an encoded `%` once you decide to decode local destinations at all. The `%XX`-present guard keeps the common literal-`%` name working (case 6, `50% off.md`) but cannot save case 7.

So the two halves have different characters, and splitting them is reasonable:

- **Unbracketing** is pure spec conformance with no trade-off. It fixes cases 1, 4 and 6 and cannot make anything worse, because `<...>`-wrapped text is never a valid destination as-is.
- **Percent-decoding** fixes case 2 and is what most Markdown editors do, but it is a policy choice with the case-7 ambiguity attached. If the maintainers would rather not take it, the bracket half stands alone.

---

## Notes for us, not for the issue

Local equivalents, both in `markdown-config.el`: `markdown-config--normalize-link-path` (the helper) and the two `:around` advices `markdown-config--fontify-image-normalize-dest` and `markdown-config--reroute-link-button`. The advice on the image fontifier rebinds `treesit-node-text` for the dynamic extent of the call rather than `expand-file-name`, because the latter is a C primitive and redefining it forces native-comp trampoline rebuilds on every fontify pass. The upstream patch has no such constraint, since it changes the call site directly.

Note that our local advice also reroutes non-Markdown local files into `dired`. That is our policy and is deliberately **not** part of this submission — the patch keeps upstream's `find-file`-for-everything behaviour and changes only which string `find-file` receives.

If only the bracket half is accepted, our advices still need the decoding half locally, since the Obsidian-era notes contain `%20`-encoded paths.
