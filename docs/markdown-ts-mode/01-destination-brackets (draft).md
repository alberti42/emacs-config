# Draft: pointy-bracket link destinations `<...>` are not recognised

Item 1 of `00-upstream-candidates (unfiled).md`. Files: `destination-repro.el` (shared reproducer) and `01-destination-brackets.patch` (`git format-patch` output, so it carries the ChangeLog commit message — attach this to the bug as-is). Committed on `fix/markdown-ts-destination-brackets` in the local fork as `7ce8e347e17`, a single commit directly over `master` at `2d5657b9dcb`.

Percent-encoded destinations are a **separate** submission — see `02-destination-percent-encoding (draft).md`. This one is pure CommonMark conformance with no option and no trade-off; that one is a convention borrowed from URIs and needs a user option. Keeping them apart means this patch can go in on its own merits.

Route, per `00-upstream-candidates (unfiled).md`: send the body below to debbugs via `M-x report-emacs-bug` with `01-destination-brackets.patch` attached — that is the maintainer's stated preference, the lab repo being "less recommended" for filing. Then mirror the same body into a lab issue titled with `(bug#NNNNN)`, for the discussion they do prefer to have on GitHub. Revised patches are replies to `NNNNN@debbugs.gnu.org`, never new filings.

Prose below is deliberately unwrapped, one line per paragraph, so it pastes into a GitHub issue without hard-wrap artifacts. For the debbugs copy, send plain text — flatten any table and drop the link syntax.

---

<!-- ltex: language=en-GB -->

## Title

`markdown-ts-mode`: link destinations wrapped in `<...>` are not recognised (a bracketed URL is opened with `find-file`)

## Body

Patch attached. Happy to keep the discussion on the lab tracker if that's easier to follow than a mail thread — treat the patch as a proposal rather than a finished thing, and say if you'd rather it were shaped differently.

### Summary

CommonMark lets a link destination be wrapped in pointy brackets, and *requires* that wrapping when the destination contains spaces ([spec 0.31.2, section 6.3 "Links"](https://spec.commonmark.org/0.31.2/#links)). `markdown-ts-mode` never removes the wrapper, so the brackets travel with the destination everywhere it is used. Two consequences, the second easy to miss:

- `[a](<my file.md>)` is passed to `find-file` as the literal string `<my file.md>`, which opens a new empty buffer under that name instead of the existing file.
- `[a](<https://example.com/x?a=1&b=2>)` is passed to **`find-file`** rather than `browse-url`. The scheme test in `markdown-ts--make-link-button` is `(string-match-p "\`[a-z]+:" url)`, and with the brackets attached the string begins with `<`, so no scheme ever matches and an ordinary bracketed URL is treated as a relative file name.

`markdown-ts--fontify-image` reads the same node text and resolves it with a bare `expand-file-name`, so `![a](<my pic.png>)` fails the `file-exists-p` guard and the image silently never renders.

### Why it matters

In Markdown there's no other way to write a file name with a space in it. Leave the space bare and you don't get an inline link at all — `[a](my file.md)` parses as the shortcut link `[a]`, which the grammar is right to do — so `<...>` is the only spelling available, and it's the one that doesn't work.

The bracketed-URL case is worse than a link that just fails to open: `find-file` on a URL-shaped string isn't inert. You end up visiting a nonsense relative path, and saving that buffer would create it.

### Reproducing

`destination-repro.el` is attached. It stubs `find-file` and `browse-url`, so running it opens nothing and browses nowhere. `emacs -Q --batch -l destination-repro.el` on current master gives:

```
 #  destination as written       handed to
 -- ---------------------------- ------------------------ ----
 1  <my target.md>               find-file "<my target.md>" FAIL   bracketed name with a space
 4  my target.md                 find-file "d"            PASS   control: bare space cannot name the file
 5  plain.md                     find-file "plain.md"     PASS   control: plain relative name
 6  <https://ex.com/x?a=1&b=2>   find-file "<https://ex.com/x?a=1&b=2>" FAIL   bracketed URL
 7  https://ex.com/q?s=a%20b     browse-url "https://ex.com/q?s=a%20b" PASS   control: URL keeps its escapes
 8  <50% off.md>                 find-file "<50% off.md>" FAIL   bracketed name with a literal %
 9  <100%25 done.md>             find-file "<100%25 done.md>" FAIL   bracketed name literally containing %25
```

(Cases 2, 3 and 10 in that reproducer concern percent-encoding and belong to the other report; they are unaffected by this patch.)

Or by hand: make a file called `my target.md`, put `[a](<my target.md>)` in a sibling `.md` buffer, and hit `RET` on the label. You get an empty buffer named `<my target.md>` instead of the file.

### Suggested fix

Attached as `01-destination-brackets.patch` — one helper and two call sites:

- `markdown-ts--unbracket-destination` strips a matched `<...>` pair.
- `markdown-ts--make-link-button` unwraps **once at the top**, before the cond. That is what fixes the bracketed-URL case, since the scheme test then sees `https:`, and it also makes `help-echo` show the destination rather than its delimiters. Doing it here rather than at each extraction site covers inline links, reference links and autolinks in one change, because they all build their button through this function.
- `markdown-ts--fontify-image` unwraps at extraction, so the `https?://` remote test is correct for a bracketed remote image too.

With the patch, cases 1, 6, 8 and 9 above become `PASS` and the controls are unchanged.

I don't think this can break anything: a `<...>`-wrapped string is never usable as a destination as it stands, so nothing that works today changes behaviour.
