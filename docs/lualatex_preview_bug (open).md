# LuaLaTeX preview-latex: "referenced object has wrong type others; should be obj"

## The symptom

When running `preview-latex` (`C-c C-p C-b` or `C-c C-p C-e`) on a LuaLaTeX
document, the region compilation fails with a fatal error:

```
error: (pdf backend): referenced object has wrong type others; should be obj
==> Fatal error occurred, no output PDF file produced!
```

The preview PNG is never generated; Ghostscript aborts with "Catalog dictionary
not located in file".

## The document context

The bug was observed on a document using:

- `% !TeX program = lualatex`
- A custom class that loads fontspec, unicode-math (STIX Two Math), hyperref,
  tcolorbox, tikz, and microtype.

## Root cause

LuaTeX's PDF backend uses `\pdfvariable objcompresslevel` (default: 1) to put
PDF objects into compressed object streams.  When those objects are later
referenced as regular (type `obj`) objects — which happens at PDF finalization
— LuaTeX fatally aborts because the objects have type `others`
(reserved/uninitialized slots in a compressed stream), not `obj`.

### Two-phase preview compilation

`preview-latex` uses a two-phase approach:

**Phase 1 — ini run** (`preview-cache-preamble`)

- Runs the full document with `luatex -ini` to dump a format (`.fmt`).
- During preamble loading (before `\begin{document}`), packages like hyperref
  create 3 PDF objects (catalog, info dict, etc.).  With `objcompresslevel=1`,
  these are stored in compressed streams and baked into the format as type
  `others`.

**Phase 2 — region run**

- Runs `luatex &formatname "/AUCTEXINPUT{_region_.tex}"`.
- Restores the format, which includes the 3 "others"-type PDF objects.
- At PDF finalization, LuaTeX tries to reference those objects as type `obj` →
  fatal error.

### Why `preview-default-preamble` is too late

`preview-LaTeX-command` embeds `preview-default-preamble` inside
`\AtBeginDocument{...}`, so anything added there runs at `\begin{document}`,
which is **after** the preamble packages have already created the 3 offending
PDF objects.  Adding `\pdfvariable objcompresslevel 0\relax` to
`preview-default-preamble` therefore does not fix the ini run.

### Why `\pdfvariable` does not survive format dumps

`\pdfvariable objcompresslevel` is a PDF backend parameter, not a TeX register.
It is not preserved in the format file.  Even if set during the ini run, it
resets to default (1) when the format is loaded in the region run.

## Required fixes (both are necessary)

### Fix 1 — ini run: inject before document loading

Modify `preview-LaTeX-command` to prepend `\pdfvariable objcompresslevel
0\relax` **right after `\nonstopmode\nofiles`**, before any `\input` that loads
the document.  This ensures `objcompresslevel=0` when hyperref creates the 3
initial PDF objects, so they are created as `obj` type and baked into the format
correctly.

```elisp
(setq preview-LaTeX-command
      '("%`%l \"\\nonstopmode\\nofiles\\pdfvariable objcompresslevel 0\\relax\
\\PassOptionsToPackage{" ("," . preview-required-option-list) "}{preview}\
\\AtBeginDocument{\\ifx\\ifPreview\\undefined"
        preview-default-preamble "\\fi}\"%' \"\\detokenize{\" %(t-filename-only) \"}\""))
```

### Fix 2 — region run: patch `\AUCTEXINPUT` in the ini file

`preview-cache-preamble` writes a `.ini` file that defines the `\AUCTEXINPUT`
macro.  That macro is baked into the `.fmt` and used to load each snippet during
the region run.  Advise `preview-cache-preamble` to patch the string before it
is written to disk, prepending `\pdfvariable objcompresslevel 0\relax` inside
`\AUCTEXINPUT`:

```elisp
(define-advice preview-cache-preamble
    (:around (orig-fun &rest args) fix-luatex-objcompresslevel)
  (cl-letf* ((orig-write-region (symbol-function 'write-region))
             ((symbol-function 'write-region)
              (lambda (start end file &rest rest)
                (when (stringp start)
                  (setq start
                        (replace-regexp-in-string
                         "\\\\def\\\\AUCTEXINPUT##1{"
                         "\\def\\AUCTEXINPUT##1{\\pdfvariable objcompresslevel 0\\relax "
                         start nil t)))
                (apply orig-write-region start end file rest))))
    (apply orig-fun args)))
```

The original `\AUCTEXINPUT` definition in `preview.el` (line 4339):

```
\def\AUCTEXINPUT##1{\catcode`/ 12\relax\catcode`\ 9\relax\input\detokenize{##1}\relax}
```

After patching:

```
\def\AUCTEXINPUT##1{\pdfvariable objcompresslevel 0\relax \catcode`/ 12\relax\catcode`\ 9\relax\input\detokenize{##1}\relax}
```

## Current status (as of 2026-04-14)

Both fixes are implemented in `latex-config.el` (the `use-package preview`
block).  **The bug still reproduces.**  The error log confirms that the region
run still hits the fatal "others" type error, meaning the ini run is still
producing a format with the 3 "others"-type objects, or the region run is still
creating new ones with `objcompresslevel > 0`.

### Suspects and next investigation angles

1. **Is fix 1 actually taking effect?**  Check the `prv_*.log` (ini run log in
   `._aux/`) for `\pdfvariable`.  If it appears inside `\AtBeginDocument` in the
   log, the `setq preview-LaTeX-command` was not applied before the format was
   rebuilt.  Steps:
   - `M-: (setq preview-dumped-alist nil)` to clear the in-memory cache.
   - Delete `._aux/prv_*.fmt` and `._aux/prv_*.ini`.
   - `C-c C-p C-b` to trigger a fresh ini run.
   - Grep `._aux/prv_*.log` for `objcompress` and verify placement.

2. **Is fix 2 actually taking effect?**  The `.ini` file is deleted after the
   format dump (`delete-file dump-file` in `preview-cache-preamble`), so you
   cannot inspect it post-hoc.  Add a `message` call inside the `write-region`
   lambda to confirm it fires, or write the patched string to a side file for
   inspection.

3. **Alternative: disable object compression globally in the class.**  If the
   custom class or any loaded package resets `objcompresslevel`, the fix will not
   hold.  Add `\pdfvariable objcompresslevel 0\relax` directly in the document
   preamble (after `\documentclass`) as a belt-and-suspenders measure.

4. **Alternative approach: use `preview-undump-replacements`.**  This
   customizable list controls the region run command template.  It may be
   possible to inject `\pdfvariable objcompresslevel 0\relax` here without
   patching `\AUCTEXINPUT`.

5. **Alternative approach: use `--lua` script.**  LuaTeX accepts a `--lua`
   flag pointing to a Lua script that runs before TeX starts.  The script
   could call `pdf.setobjcompresslevel(0)` before the format is loaded.
   This would bypass the TeX-level patching entirely.

6. **Unrelated noise removed:** microtype caused cascading Lua errors during ini
   run (`attempt to index a nil value (global 'microtype')`).  The user
   commented out microtype in the document; this error is gone.

## Key source locations

- `preview.el` (AUCTeX):
  - Line 3086: `preview-default-preamble` defcustom
  - Line 3096: `preview-LaTeX-command` defcustom — the ini command template
  - Line 4290: `preview-cache-preamble` function body
  - Line 4334: the `write-region` call that writes the `.ini` file
  - Line 4339: `\def\AUCTEXINPUT##1{...}` — the macro patched by fix 2
- `latex-config.el` (this repo): `use-package preview` block

## Related

- microtype + LuaTeX format dumps: microtype uses Lua code that is not
  preserved in format dumps, causing `attempt to index a nil value (global
  'microtype')` during the region run.  Workaround: comment out microtype, or
  add `\PassOptionsToPackage{disable}{microtype}` before the ini run (can be
  added to `preview-default-preamble`, but that is inside `\AtBeginDocument`
  so it may or may not help depending on when microtype registers its Lua
  callbacks).
