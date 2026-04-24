# `org-latex-preview`: detect stale cached `.fmt` after TeX engine upgrade

## Symptom

After upgrading TeX Live (e.g. 2025 → 2026, or any in-place engine update via
`tlmgr`), `org-latex-preview` fails silently on the first preview in every
buffer. The `*Org Preview LaTeX Output*` buffer shows:

```
! /path/to/.cache/org-persist/<hash>/<root>-<preamble>.fmt made by different
executable version, strings are different
(Fatal format file error; I'm stymied)
```

…followed by `*Org Preview Convert Output*` complaining it `can't open
... .dvi` (because pdfTeX exited 252 and produced no DVI). No previews render,
and no hint in the minibuffer that the cache is at fault.

## Root cause

`org-latex-preview--precompile` caches the precompiled preamble `.fmt` keyed
on the preamble hash (via `org-persist`). The cache key does not include any
fingerprint of the TeX engine binary that produced it. pdfTeX refuses format
files built by a different engine version — `.fmt` files encode runtime
memory layout (pointer widths, string-pool offsets) that is binary-tied. So
after an engine upgrade the cache looks valid from Org's perspective,
`org-latex-preview--precompile` returns the stale path, and every fragment
compile blows up.

## Why it's painful

- The error is only visible in `*Org Preview LaTeX Output*`; otherwise
  previews just "don't work".
- There's no documented relationship between TeX Live upgrades and the
  `org-persist` cache, so diagnosing requires reading `org-latex-preview.el`
  internals.
- System-wide `.fmt` files shipped by TeX Live are rebuilt automatically by
  `fmtutil-sys` during the upgrade. User-precompiled `.fmt` files in
  `$XDG_CACHE_HOME/org-persist/` don't go through that machinery, so they
  silently rot.
- Every TeX Live release essentially guarantees a fresh round of broken
  installs for `org-latex-preview` users who must then reverse-engineer Org
  to understand why math previews stopped working.

## Proposed fix

Cheap mtime check: if the TeX engine binary is newer than a cached `.fmt`,
that `.fmt` was built against an older engine — delete it so the next preview
rebuilds via `pdftex -ini`. Cost: two `stat(2)` calls per `.fmt`, sub-
millisecond.

## Working implementation (tested locally)

Below is the exact code I dropped into my `:config` block of `use-package
org` and verified. It runs once when Org loads, before the `org-mode` body's
startup-preview call, so the first preview in a fresh session always sees a
valid cache. For upstream integration, a good home could be at load time of
org-mode or math-preview-mode.

```elisp
(when-let* ((pdftex (executable-find "pdftex"))
            (cache (expand-file-name
                    "org-persist/"
                    (or (getenv "XDG_CACHE_HOME") "~/.cache")))
            ((file-directory-p cache)))
  (dolist (fmt (directory-files-recursively cache "\\.fmt\\'"))
    (when (file-newer-than-file-p pdftex fmt)
      (message "org-latex-preview: purging stale %s"
               (file-name-nondirectory fmt))
      (delete-file fmt)
      ;; Sibling metadata file: same stem minus the `-<preamble-hash>.fmt'
      ;; suffix.  Example:
      ;;   <dir>/ROOT-HASH-PREAMBLE.fmt  →  <dir>/ROOT-HASH
      (let ((meta (replace-regexp-in-string "-[^-/]+\\.fmt\\'" "" fmt)))
        (when (and (not (equal meta fmt)) (file-exists-p meta))
          (delete-file meta))))))
```

Notes on the code:

- Hardcodes `pdftex`; a real upstream version would iterate over every
  compiler in `org-latex-preview-compiler-command-map` (pdflatex, lualatex,
  xelatex) and compare each to its respective cached format files.
- The metadata sibling-file regex strips the `-<preamble-hash>.fmt` suffix
  to recover the `org-persist` index entry that must be removed alongside
  the `.fmt` itself. Observed layout in `org-persist/<hh>/`:
  ```
  3876a7-89b2-4d62-8bb5-1d4045eb8d76                              (metadata)
  3876a7-89b2-4d62-8bb5-1d4045eb8d76-21e52f04705fa387b835…fmt     (format)
  ```
- `file-newer-than-file-p` follows symlinks, which is what we want:
  `pdflatex` is typically a symlink to `pdftex`, and the mtime that matters
  is that of the resolved engine binary.

## Configuration options

Probably right to have this enabled by default — the failure mode can give a
lot of headaches to the user, who is not familiar with the inner mechanics
of `.fmt` precompiled files. The check for "freshness" is effectively free. A
`defcustom org-latex-preview-validate-fmt-freshness` (default `t`) would let
power users opt out if they're doing something clever (e.g. binding older
engines via `TEXMF` and wanting to keep the corresponding cache).
## 
## Reproduction

```sh
# With an org buffer that has previously produced a .fmt:
sudo touch "$(which pdftex)"

emacs some-doc-with-latex.org
# → preview fails with exit 252; *Org Preview LaTeX Output* shows
#   "made by different executable version".
```

With the purge in place, the first preview after `touch` rebuilds the `.fmt`
cleanly (one-time ~1s `pdftex -ini` stall) and subsequent previews are
instant.
