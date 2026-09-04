<!-- ltex: language=en-US -->

## The bug in one line

`markdown-ts-mode`: link destinations wrapped in `<...>` are not recognized (a
bracketed URL is opened with `find-file`).

### Bug summary

CommonMark lets a link destination be wrapped in pointy brackets, and *requires*
that wrapping when the destination contains spaces ([spec 0.31.2, section 6.3
"Links"](https://spec.commonmark.org/0.31.2/#links)). `markdown-ts-mode` never
removes the wrapper. Thus, the angle brackets remain in the destination string. As a consequence, this gives rise to three related bugs:   

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

In Markdown there's no other official way to write a file name with a space in
it. Quoting the [official specs](https://spec.commonmark.org/0.31.2/):

> The destination can only contain spaces if it is enclosed in pointy brackets

The bracketed-URL case is worse than a link that just fails to open: `find-file`
on a URL-shaped string isn't inert. You end up visiting a nonsensical relative
path, and saving that buffer would create it.

### Related issues on markdown-ts-mode-lab

I checked on

https://github.com/LionyxML/markdown-ts-mode-lab/issues

but I could not find any issue related to destinations wrapped by angle
brackets.

### Patch

The patch is attached. "Unbracketing" is performed in
'markdown-ts--make-link-button' rather than at each consumer site, so that it
directly covers inline links, reference links and autolinks at once, since they
all build their button through it.

Please treat the patch as a proposal rather than a finished thing. I am happy to change it following the maintainers' advice.
