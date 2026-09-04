# Draft (PARKED): percent-encoded local link destinations are never decoded

Item 2 of `00-upstream-candidates (unfiled).md`. Files: `destination-repro.el` (shared reproducer) and `02-destination-percent-encoding.diff`, which applies **on top of** `01-destination-brackets.patch`.

**Parked — do not file as it stands.** The patch decodes after unbracketing, which the design note at the end rejects; it needs reworking first.

Deliberately separate from the bracket report, and the scope is narrower than the title suggests: it concerns destinations written *without* angle brackets. Removing `<...>` is CommonMark syntax and has no downside; percent-decoding is a URI reading of the destination that CommonMark does not ask for, so it is a policy question, needs a user option, and carries one irreducible ambiguity. Bundling the two would make the uncontroversial half hostage to this one.

Route, per `00-upstream-candidates (unfiled).md`: debbugs via `M-x report-emacs-bug` with the patch attached, then a lab issue mirroring it under `(bug#NNNNN)` for discussion. This one carries a real design choice (the option and its default), so it is worth flagging in the report that you would rather settle that on the lab issue than in a mail thread.

Prose below is deliberately unwrapped, one line per paragraph, so it pastes into a GitHub issue without hard-wrap artifacts. For the debbugs copy, send plain text — flatten any table and drop the link syntax.

---

## Title

`markdown-ts-mode`: percent-encoded local link destinations (written without angle brackets) are not decoded, so Obsidian-style links and image embeds do not resolve

## Body

Patch attached, and a companion to the bracket one. There's a genuine design choice in it — whether to decode at all, and what the option should default to — so I'm happy to hash that out on the lab tracker if that's easier than a mail thread.

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

---

## Design note: brackets mean verbatim (supersedes the option below)

An angle-bracketed destination should be taken **verbatim** — no percent-decoding inside `<...>`. Decoding then applies only to destinations written *without* brackets. The two forms stop overlapping and each says something definite:

| written | reading | resolves to |
| --- | --- | --- |
| `[a](my%20file.md)` | no brackets, so a URI reference | `my file.md` |
| `[a](<my file.md>)` | brackets, so verbatim | `my file.md` |
| `[a](<my%20file.md>)` | brackets, so verbatim | `my%20file.md` |
| `[a](<100%25 done.md>)` | brackets, so verbatim | `100%25 done.md` |

This is worth more than the `markdown-ts-percent-decode-destinations` option, because it fixes the case the option only worked around. A file whose name literally contains `%25` becomes reachable by writing it in brackets — the document carries the disambiguation, per link, instead of a global flag forcing one answer on every link in every file. The option may still be wanted by someone who objects to decoding at all, but it stops being the escape hatch for that corner.

Two honest caveats for the report:

- **This is a convention, not something CommonMark states.** The spec gives `<...>` no "verbatim" semantics; it is only a delimiter form that permits spaces and parens. So the argument has to be made on utility, not conformance — unlike the bracket fix, which is pure conformance.
- **It costs nothing in practice.** The combined form `<…%XX…>` does not occur in the 972-note vault measured above (0 of 696), and it is pointless to write anyway, since brackets already allow a literal space. So no existing document changes meaning.

Consequences for the attached patch, which does **not** implement this yet: `markdown-ts--destination-file-name` currently unbrackets and *then* decodes, so it resolves `<my%20file.md>` to `my file.md`. Under this rule it must decode only when no brackets were present — which also means the reproducer's case 3 expectation flips to `my%20target.md`, and case 9 becomes a `PASS` rather than the known-unfixable failure.
