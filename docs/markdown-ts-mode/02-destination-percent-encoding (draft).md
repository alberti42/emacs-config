# Draft: percent-encoded local link destinations are never decoded

Item 2 of `00-upstream-candidates (unfiled).md`. Files: `destination-repro.el` (shared reproducer) and `02-destination-percent-encoding.diff`, which applies **on top of** `01-destination-brackets.patch`.

Deliberately separate from the bracket report. Removing `<...>` is CommonMark syntax and has no downside; percent-decoding is a URI reading of the destination that CommonMark does not ask for, so it is a policy question, needs a user option, and carries one irreducible ambiguity. Bundling the two would make the uncontroversial half hostage to this one.

Route, per `00-upstream-candidates (unfiled).md`: open this as a **lab issue first**, offering the patch, since the maintainers asked for discussion there and `patches.md` has an unsubmitted link-handling entry this could collide with. Once they agree, file it at debbugs with the patch attached (only a bug there can carry a fix into Emacs core) and add `(bug#NNNNN)` to the lab issue title. Revised patches are replies to `NNNNN@debbugs.gnu.org`, never new filings.

Prose below is deliberately unwrapped, one line per paragraph, so it pastes into a GitHub issue without hard-wrap artifacts. For the debbugs copy, send plain text — flatten any table and drop the link syntax.

---

## Title

`markdown-ts-mode`: percent-encoded local link destinations are not decoded, so Obsidian-style links and image embeds do not resolve

## Body

Same as the bracket one — keeping it here first so it's easier to follow, and I'll file it at `bug-gnu-emacs` whenever you say. Patch is written and tested, but there's a real design choice in it (the option and its default), which is exactly the sort of thing worth settling here rather than on debbugs.

### Summary

A local destination written with percent-escapes is used verbatim, so `[a](my%20file.md)` is handed to `find-file` as `my%20file.md` and never reaches `my file.md`. `markdown-ts--fontify-image` resolves the same text with a bare `expand-file-name`, so `![a](my%20pic.png)` fails its `file-exists-p` guard and the image silently never renders.

Strictly speaking CommonMark takes a destination as written and doesn't ask you to decode anything — which is why I'm proposing this as an option rather than just doing it.

### Why it matters

Plenty of Markdown tools emit percent-encoded local paths, so this bites anyone reading files written elsewhere. Obsidian is the clearest case — it percent-encodes and doesn't use pointy brackets at all.

Measured over a 972-note Obsidian vault:

```
percent-encoded, ](...%XX...)   696
bracketed,       ](<...>)         0
both together                     0
```

63 of those 696 are image embeds, which is the `markdown-ts--fontify-image` half. The escapes are not only `%20`: that vault uses `%20` (2718), `%3A` (355), and UTF-8 sequences such as `%CC%88` for a combining diaeresis — which matters for the implementation, below.

So in practice the two spellings aren't interchangeable — a tool picks one, and Obsidian picks this one. Combining them (`<my%20file.md>`) would be pointless anyway, since brackets already let you write a literal space, and sure enough it never shows up in that corpus. The reproducer covers it just for completeness.

### Reproducing

`destination-repro.el` is attached (it stubs `find-file` and `browse-url`, so it opens nothing). With the bracket patch applied (branch `fix/markdown-ts-destination-brackets`) but not this one:

```
 #  destination as written       handed to
 -- ---------------------------- ------------------------ ----
 2  my%20target.md               find-file "my%20target.md" FAIL   percent-encoded name with a space
 3  <my%20target.md>             find-file "my%20target.md" FAIL   bracketed AND percent-encoded
 7  https://ex.com/q?s=a%20b     browse-url "https://ex.com/q?s=a%20b" PASS   control: URL keeps its escapes
 10 Fo%CC%88rster%20resonance.md find-file "Fo%CC%88rster%20resonance.md" FAIL   UTF-8 percent-escapes
```

### Suggested fix

Attached as `02-destination-percent-encoding.diff`, applying on top of the bracket patch.

- New option `markdown-ts-percent-decode-destinations`, default `t`. Set it to `nil` for strict CommonMark behaviour.
- `markdown-ts--destination-file-name` unwraps any `<...>`, then decodes — but only when the string actually contains a `%XX` escape, so a file name with a literal `%` and no valid escape after it (`50% off.md`) is untouched.
- Decoding is applied **only** in the local-file branch of `markdown-ts--make-link-button` and the local branch of `markdown-ts--fontify-image`. A URL keeps its escapes, since decoding a query string would corrupt it (case 7 is the guard against that).

Two things worth flagging:

**Decoding must go through `decode-coding-string`, not `url-unhex-string` alone.** Percent-escapes encode UTF-8 *bytes*, so unhexing `Fo%CC%88rster.md` yields a unibyte string of raw bytes. On a system whose `file-name-coding-system` is UTF-8 that string still finds the file, so it is easy to miss — but the buffer is then visited under the name `Fo\314\210rster.md`. Decoding back to characters gives `Förster.md`.

**The default.** I went with `t`, on the grounds that the symptom being reported is "my link doesn't open my file" and a fix that's off by default doesn't fix it — and the `%XX` guard means plain paths are untouched either way. If you'd rather it defaulted to `nil` for strict conformance, that's a one-line change and I have no strong feelings.

Also: the `:version` in the patch says `32.1`; adjust to whatever the next release actually is.

### The one case this cannot fix

A file whose name literally contains `%25` is indistinguishable from an encoded `%` once you decode at all. With the option on, a link to `<100%25 done.md>` resolves to `100% done.md`:

```
 9  <100%25 done.md>   find-file "100% done.md"   FAIL
```

That's inherent rather than a flaw in the patch, and it's really the reason for the option — anyone with names like that sets it to `nil` and keeps correct behaviour. It's also why I split this from the bracket fix, which has no such corner.
