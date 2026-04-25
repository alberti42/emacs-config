# Bug: state-helper defuns in `jupyter-monads.el` are byte-compiled before their macros are defined

## TL;DR

> Tip-of-trunk has a crashing bug: `M-x jupyter-repl-associate-buffer` from a fresh state starts the
kernel but leaves the source buffer unassociated, because `jupyter-get-client` (and four siblings
added in `a0871ba`) are defined in `jupyter-monads.el` *above* the macros they expand into — so the
byte-compiler emits them as plain function calls and they crash with `(void-variable state)` at
runtime. The byte-compiler already warns: `Warning: macro 'jupyter-do' defined too late`.
>
> **The fix is a one-file, mechanical move: relocate five `defun`s below the `jupyter-mlet*` / `jupyter-do` macros.** No behaviour change, no API change, 49 +/49 -.
>
> The detailed analysis below (repro, bytecode diff, call chain through
`jupyter-repl-sync-execution-state`) is included for completeness so you can verify the diagnosis
without re-tracing it from scratch — feel free to skim it.

---

## Summary

Five state-helper functions added in commit a0871ba ("More convenience functions to work
with state", 2025-12-18) — `jupyter-get-client`, `jupyter-push`, `jupyter-pop`,
`jupyter-set-client`, `jupyter-at-point` — are defined at the top of `jupyter-monads.el`,
**before** the macros they expand into (`jupyter-mlet*`, `jupyter-do`).

The byte-compiler processes the file top-to-bottom; at the point those defuns
are compiled, the macros are not yet known, so the calls are emitted as plain
function calls instead of being macro-expanded inline. At runtime, calling
e.g. `jupyter-get-client` signals `(void-variable state)` — the body
`(let ((client (if (listp state) ...))) ...)` is evaluated in the defun's
scope, where `state` is unbound, before being passed as an argument to the
function-call form of `jupyter-mlet*`.

The byte-compiler does emit a warning that points exactly at the cause:

```
jupyter-monads.el:160:11: Warning: macro 'jupyter-do' defined too late
```

(An analogous condition exists for `jupyter-mlet*`, but `jupyter-do` is the
one that triggers the warning because it is also used inside `jupyter-pop`.)

The downstream symptom is a hard failure of `jupyter-repl-sync-execution-state`
during fresh REPL startup, which aborts `jupyter-bootstrap-repl` before its
`:after` method runs and leaves source buffers without an associated client
after `M-x jupyter-repl-associate-buffer` (the second invocation works,
because the REPL exists by then and the no-client branch is no longer taken).

**File:** `jupyter-monads.el`
**Introduced:** commit a0871ba (2025-12-18, "More convenience functions to
work with state")
**Surfaced by:** commit d3f6bc8 (2025-12-15, "jupyter-repl-sync-execution-state:
Refactor"), which made `jupyter-repl-sync-execution-state` call the
broken `jupyter-get-client` from inside `jupyter-repl-mode`.
**Severity:** hard failure — `jupyter-repl-associate-buffer` from a fresh
state appears to start a kernel but never connects the source buffer to it.

---

## Reproduction Steps

1. Check out tip-of-trunk (verified at 3b9caed).
2. From any source buffer whose `major-mode` matches a kernel's language mode
   (e.g. a `.py` file in `python-ts-mode`), run `M-x jupyter-repl-associate-buffer`
   from a state where no Jupyter REPL exists.
3. Answer `y` to "No REPL for `major-mode` exists. Start one?".
4. Pick a kernel.

**Result:** the kernel starts, the `*jupyter-repl[…]*` buffer is created, but
`jupyter-current-client` in the source buffer remains `nil`. The `*Messages*`
buffer contains:

```
jupyter-repl-sync-execution-state: Symbol's value as variable is void: state
```

With `(setq debug-on-error t)`, the relevant frames are:

```
Debugger entered--Lisp error: (void-variable state)
  jupyter-get-client()
  jupyter-repl-sync-execution-state()
  jupyter-repl-mode()
  …
  jupyter-bootstrap-repl(#<jupyter-repl-client …> nil t t)
  jupyter-run-repl("python3" nil t nil t)
  …
  jupyter-repl-associate-buffer(nil)
```

**Expected:** the source buffer is associated with the new REPL,
`jupyter-current-client` is set, `jupyter-repl-interaction-mode` is enabled.

A second `M-x jupyter-repl-associate-buffer` "fixes" the symptom because the
`else` branch of `jupyter-repl-associate-buffer` does the association
directly, never going through the broken sync path.

---

## Root Cause

The relevant slice of `jupyter-monads.el` (line numbers from 3b9caed):

```elisp
75   (defun jupyter-get-client ()                ; uses jupyter-mlet*
84   (defun jupyter-push (s)                     ; uses jupyter-mlet*
89   (defun jupyter-pop ()                       ; uses jupyter-mlet*, jupyter-do
99   (defun jupyter-set-client (client)          ; uses jupyter-mlet*
108  (defun jupyter-at-point (action)            ; uses jupyter-mlet*
124  (defun jupyter-bind (mvalue mfn) …)
131  (defmacro jupyter-with-bindings* …)
146  (defmacro jupyter-mlet* …)                  ; <-- defined AFTER its callers
160  (defmacro jupyter-do …)                     ; <-- defined AFTER its callers
```

The byte-compiler emits the warning:

```
jupyter-monads.el:160:11: Warning: macro 'jupyter-do' defined too late
```

Inspecting the bytecode of `jupyter-get-client` confirms what happened:

```
;; BEFORE the fix — macro NOT expanded:
#[0 "����<�� @�� ����\"…" [state jupyter-mlet* nil cl-typep jupyter-kernel-client …] …]
;;                                          ^^^^^ ^^^^^^^^^^^^^^
;;                                          free  treated as a function symbol
```

The constants vector starts with `state`. The compiled body looks up `state`
as a *variable* at runtime — which is exactly what `(void-variable state)`
reports. The intended macro expansion would have produced a closure
`(jupyter-bind (jupyter-get-state) (lambda (state) …))` that captures `state`
as a lambda parameter, with no free reference.

The error escapes through three layers and ends up swallowing the buffer
association:

1. `jupyter-repl-sync-execution-state` calls `jupyter-get-client` (transitively,
   via `jupyter-mlet*` macroexpansion in the outer scope where it *was* expanded
   correctly — but the inner `jupyter-get-client` still has the broken bytecode).
2. The error propagates out of `jupyter-repl-sync-execution-state`, which is
   called from `jupyter-repl-mode` (`jupyter-repl.el:1780`).
3. `jupyter-repl-mode` was being run inside the primary method of
   `jupyter-bootstrap-repl`, via `jupyter-with-repl-buffer`. The error aborts
   the primary method, so the CLOS `:after` method is **skipped**, and the
   `jupyter-repl-associate-buffer` call inside it never runs.

---

## Fix

Reorder the helpers so the macro definitions precede their callers. The
five functions are moved below `jupyter-mlet*`, `jupyter-do`, and
`jupyter-run-with-state` (the last is needed by `jupyter-at-point`).

After the fix, recompiling `jupyter-monads.el` produces no
`defined too late` warnings, and the bytecode of `jupyter-get-client`
becomes:

```
;; AFTER the fix — macro expanded inline:
#[0 "���� ��\"…" [jupyter-bind jupyter-get-state #[257 …]] …]
;;                ^^^^^^^^^^^^^ ^^^^^^^^^^^^^^^^^
;;                jupyter-bind directly invoked with the state-thunk closure
```

`state` is no longer in the constants vector; it lives in the inner closure's
argument list, exactly as the source intends.

No behavioural change in interpreted mode — only the byte-compiled output
differs. All five reordered functions are simple `defun`s with no mutual
recursion, so the move is purely lexical.

---

## Patch

Single commit, one file, `jupyter-monads.el`. The diff is mechanical: cut
the five `defun`s from lines 75–122 of `3b9caed` and paste them between
`jupyter-run-with-state` (originally line 173) and `jupyter-run-with-io`
(originally line 179).

```
1 file changed, 49 insertions(+), 49 deletions(-)
```

---

## Verification

Smoke test in batch:

```sh
emacs --batch --quick -L . \
  -l jupyter-base.elc -l jupyter-monads.elc \
  --eval "(condition-case err
             (let ((c (jupyter-get-client)))
               (princ (format \"%S\" (functionp c))))
           (error (princ (format \"ERR: %S\" err))))"
```

- Before: `ERR: (void-variable state)`
- After:  `t`

Interactive: `M-x jupyter-repl-associate-buffer` from a fresh `.py` buffer
now associates the source buffer with the freshly-started REPL on the first
invocation; `jupyter-current-client` is set and
`jupyter-repl-interaction-mode` is enabled.

---

## Related

- d3f6bc8 ("jupyter-repl-sync-execution-state: Refactor") is what made
  `jupyter-repl-sync-execution-state` call `jupyter-get-client`. The
  refactor itself is fine; it merely surfaced the latent bug from `a0871ba`.
- The fix does not need to touch `jupyter-repl.el`. The downstream behaviour
  there (`:after` association, error handling in `jupyter-repl-mode`) is
  fine, based on the assumption that `jupyter-repl-sync-execution-state` does
  not throw during normal startup — an assumption that holds again once the
  monads file is fixed.
