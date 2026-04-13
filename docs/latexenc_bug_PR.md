# Bug: `latexenc-find-file-coding-system` crashes with `wrong-type-argument sequencep t`

## Summary

`latexenc-find-file-coding-system` crashes with a `wrong-type-argument sequencep t`
error whenever `TeX-master` is set to a string buffer-locally (e.g. via AUCTeX
dir-locals or a file-local `% !TeX root =` magic comment) and the file does not
contain an explicit `TeX-master:` entry in its `Local Variables:` section.

The bug is triggered by any operation that calls `insert-file-contents` on a
`.tex` file, including the common case of `revert-buffer`.

**File:** `lisp/international/latexenc.el`  
**Introduced:** at least present in Emacs 29, 30, and 31 (verified in 31.0.50)  
**Severity:** hard crash — `revert-buffer` is completely broken for the affected
files.

---

## Reproduction Steps

1. Open a `.tex` file that sets `TeX-master` via the **first-line modeline**
   format (not a `Local Variables:` block):
   ```tex
   % -*- mode: latex; TeX-master: "problemset01.tex"; TeX-engine: luatex; -*-
   ```
2. Call `M-x revert-buffer` and confirm with `y`.

The bug also triggers whenever `TeX-master` is set to a string by any other
mechanism that does not write a `Local Variables:` block to the file, for
example:
- AUCTeX dir-locals: `((LaTeX-mode . ((TeX-master . "main"))))`
- A hook that calls `(setq-local TeX-master "main")` in response to a
  tool-specific magic comment such as `% !TeX root = main.tex`

**Result:**
```
Debugger entered--Lisp error: (wrong-type-argument sequencep t)
  latexenc-find-file-coding-system(
    (insert-file-contents "/path/to/file.tex" t nil nil if-regular))
  revert-buffer-insert-file-contents--default-function(
    "/path/to/file.tex" nil)
  revert-buffer--default(t nil)
  revert-buffer(t)
```

**Expected:** the buffer reverts normally.

---

## Root Cause

`latexenc-find-file-coding-system` is registered in `file-coding-system-alist`
for `.tex` files. Whenever `insert-file-contents` is called on a `.tex` file,
Emacs invokes this function to detect the file's coding system (e.g. by reading
`\usepackage[latin1]{inputenc}`). As a fallback — when no `inputenc` declaration
is found in the current file — it tries to locate a *master* file and read its
encoding instead.

The master-file lookup (lines 150–168 of `latexenc.el`) first searches the
buffer's `Local Variables:` section for an explicit `TeX-master:` or
`tex-main-file:` entry written in the block format:

```tex
% Local Variables:
% TeX-master: "main.tex"
% End:
```

It does **not** recognise the first-line modeline format (`% -*- ... -*-`),
even though Emacs itself reads both formats and applies them identically as
file-local variables.  When the file uses the modeline format, Emacs sets
`TeX-master` buffer-locally before `latexenc` runs, so the variable is
present — but `latexenc`'s text search finds nothing, and it falls back to
the buffer-local *variable* `TeX-master`:

```elisp
;; latexenc.el, lines 155–168
(let ((file (if (re-search-forward
                 "^%+ *\\(TeX-master\\|tex-main-file\\): *\"\\(.+\\)\""
                 nil t)
                (match-string 2)             ; correct: a string from the file
              (or (and (bound-and-true-p TeX-master)
                       (stringp TeX-master)) ; BUG: returns t, not the string
                  (bound-and-true-p tex-main-file)))))
  (dolist (ext `("" ,(if (boundp 'TeX-default-extension)
                         (concat "." TeX-default-extension)
                       "")
                 ".tex" ".ltx" ".dtx" ".drv"))
    (if (and (null latexenc-main-file)
             (file-exists-p (concat file ext))) ; crash: (concat t ".tex")
        (setq latexenc-main-file (concat file ext)))))
```

The bug is in the `or` expression on lines 159–161. The intent is to return the
string value of `TeX-master` when it is bound and is a string. However the `and`
clause evaluates to the **return value of `(stringp TeX-master)`**, which is `t`
(the boolean), not the string itself:

```elisp
;; Evaluates to t, not to the string "main":
(and (bound-and-true-p TeX-master)  ; => "main"  (non-nil, continues)
     (stringp TeX-master))          ; => t        (last form — returned!)
```

`file` therefore becomes `t`. On the very next use, `(concat t ".tex")` is
called, which signals `wrong-type-argument sequencep t` because `concat` expects
sequences, not booleans.

Compare with the sibling branch: `(bound-and-true-p tex-main-file)` correctly
returns the *value* of `tex-main-file` (a string) when it is bound and non-nil,
because `bound-and-true-p` is defined as:

```elisp
(defmacro bound-and-true-p (var)
  `(and (boundp ',var) ,var))   ; returns the value, not t
```

The `TeX-master` branch mistakenly adds a redundant `stringp` check as the last
`and` form instead of returning the value.

---

## The Fix

Add `TeX-master` as the last clause of the `and` so that the value — not the
boolean result of `stringp` — is returned:

```elisp
;; Before (buggy):
(or (and (bound-and-true-p TeX-master)
         (stringp TeX-master))        ; returns t, not the string
    (bound-and-true-p tex-main-file))

;; After (fixed):
(or (and (bound-and-true-p TeX-master)
         (stringp TeX-master)
         TeX-master)                  ; returns the string value
    (bound-and-true-p tex-main-file))
```

This mirrors exactly how `(bound-and-true-p tex-main-file)` already works for
the `tex-main-file` case.

### Full diff

```diff
--- a/lisp/international/latexenc.el
+++ b/lisp/international/latexenc.el
@@ -156,7 +156,8 @@
               (let ((file (if (re-search-forward
                                "^%+ *\\(TeX-master\\|tex-main-file\\): *\"\\(.+\\)\""
                                nil t)
                               (match-string 2)
                             (or (and (bound-and-true-p TeX-master)
-                                    (stringp TeX-master))
+                                    (stringp TeX-master)
+                                    TeX-master)
                                 (bound-and-true-p tex-main-file)))))
```

---

## Why the `stringp` guard exists

The `stringp` check is intentional: in AUCTeX, `TeX-master` is a
multi-type variable that can be set to:

| Value | Meaning |
|---|---|
| `t` | this file is its own master |
| `nil` | ask the user when needed |
| `"filename"` | explicit master file path |
| `shared` | shared master, ask once |

Only the string case carries a usable filename. The guard correctly filters out
`t`, `nil`, and `shared`. The bug is solely that the guard's *return value* was
not the string itself.

---

## Workaround (until fixed upstream)

Add the following advice to your Emacs configuration:

```elisp
;; Catch the wrong-type-argument crash in latexenc when TeX-master is a string.
;; Returns nil (undecided) so Emacs falls back to its normal coding-system
;; detection.  TeX-master is left untouched; compilation is unaffected.
(with-eval-after-load 'latexenc
  (define-advice latexenc-find-file-coding-system
      (:around (orig arg-list) fix-tex-master-type-bug)
    (condition-case nil
        (funcall orig arg-list)
      (wrong-type-argument nil))))
```

---

## Additional Notes

- The crash path is only reached when the `.tex` file contains no
  `\usepackage[...]{inputenc}` or `\inputencoding{...}` declaration (the
  primary detection path). Files that do declare `inputenc` are unaffected.
- Modern LaTeX workflows using LuaLaTeX or XeLaTeX handle Unicode natively and
  never use `inputenc`, making this crash more likely for those users.
- The `dolist` on line 162 would also crash when `file` is `nil` and
  `TeX-default-extension` is not bound, but `(concat nil "")` evaluates to `""`
  which is harmless, so `nil` is safe there. Only `t` is problematic.
