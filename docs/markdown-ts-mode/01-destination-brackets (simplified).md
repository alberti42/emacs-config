<!-- ltex: language=en-US -->

### The bug in one line

`markdown-ts-mode`: link destinations wrapped in `<...>` are not recognized (a
bracketed URL is opened with `find-file`).

### Bug summary

CommonMark lets a link destination be wrapped in pointy brackets, and *requires*
that wrapping when the destination contains spaces ([spec 0.31.2, section 6.3
"Links"](https://spec.commonmark.org/0.31.2/#links)). `markdown-ts-mode` never
removes the wrapper. Thus, the angle brackets remain in the destination
string. As a consequence, this gives rise to two directly related bugs and a
third similar bug in the image path:

- `[a](<my file.md>)` is passed to `find-file` as the literal string `<my
  file.md>`, which opens a new empty buffer under that name instead of the
  existing file.
- `[a](<https://example.com/x?a=1&b=2>)` is passed to **`find-file`** rather
  than `browse-url`. The scheme test in `markdown-ts--make-link-button` is
  `(string-match-p "\`[a-z]+:" url)`, and with the brackets attached the string
  begins with `<`, so no scheme ever matches and an ordinary bracketed URL is
  treated as a relative file name.

The third bug is manifested in `markdown-ts--fontify-image`, which reads the
same node text and resolves it with a bare `expand-file-name`, so `![a](<my
pic.png>)` fails the `file-exists-p` guard and the image silently never renders.

### On the relevance of the fix

In Markdown there's **only one official way** to write a file name with a space
in it. Quoting the [official specs](https://spec.commonmark.org/0.31.2/):

> The destination can only contain spaces if it is enclosed in pointy brackets

The bracketed-URL case, which is in today's master, has worse effects than just
a link failing to open. In fact, `find-file` ends up visiting a nonsensical
relative path, and saving that buffer would create it.

### Checked for duplicates

I could not find anything already filed about angle-bracketed destinations, in
either place:

- All 33 Emacs bugs whose subject mentions `markdown-ts` (open and archived).
  The nearest neighbours are #80625 (which introduced the clickable links) and
  #81703 (bare URLs getting a `mailto:` prefix), neither of which touches the
  destination wrapper.
- The development tracker,
  https://github.com/LionyxML/markdown-ts-mode-lab/issues (all 59 issues, open
  and closed).

### Patch

The patch is attached. "Unbracketing" is performed in
'markdown-ts--make-link-button' rather than at each consumer site, so that it
directly covers inline links, reference links and autolinks at once, since they
all build their button through it.

Please treat the patch as a proposal rather than a finished thing. I am happy to
change it following the maintainers' advice.
