;;; bookmark-aux-file.el --- Per-context auxiliary bookmark files -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Andrea Alberti

;; Author: Andrea Alberti <a.alberti82@gmail.com>
;; Version: 0.1.0
;; Keywords: convenience bookmark project
;; URL: https://github.com/alberti42/dotfiles
;; Package-Requires: ((emacs "28.1"))

;; Add an auxiliary bookmark file to stock `bookmark.el' without forking it.
;;
;; Stock bookmarks live in a single flat `bookmark-alist' serialized to one
;; file.  This library lets a buffer-local variable, `bookmark-aux-file', name
;; an *additional* bookmark file.  While that variable is set in the current
;; buffer:
;;
;; - the auxiliary file's bookmarks merge into the view (computed on demand;
;;   entries are kept verbatim, never de-duplicated -- two bookmarks that share
;;   a name but point elsewhere are distinct, and collapsing them is the user's
;;   call, not the library's);
;; - bookmarks set from such a buffer are routed to the auxiliary file, and
;;   never overwrite a same-named *global* bookmark (a set always targets the
;;   auxiliary file: it overwrites an auxiliary entry of that name if one
;;   exists, otherwise it creates a new auxiliary one);
;; - saves write each group back to its own file, in plain stock format;
;; - a *different* context's auxiliary file is never visible.
;;
;; Auxiliary entries are merged at the front of the list, exactly as stock
;; `bookmark-load' inserts a loaded file's bookmarks (\"to the front\").  The
;; only observable effect of that order is stock's own first-match rule in
;; `bookmark-get-bookmark': a bare-name lookup resolves to the auxiliary entry.
;; Both entries always remain visible in listings and completion -- nothing is
;; hidden.
;;
;; The library is deliberately policy-free: it decides nothing about *where*
;; the auxiliary file lives or *when* `bookmark-aux-file' is set.  That
;; lifecycle belongs to the consumer (dir-locals, a personal hook, `M-x', a
;; project integration).  The library only honors the variable.

;;; Commentary:
;;
;; Usage:
;;   (require 'bookmark-aux-file)
;;   (bookmark-aux-file-mode 1)
;; then arrange, however you like, for `bookmark-aux-file' to hold a path in
;; the buffers that should use an auxiliary file, e.g. via .dir-locals.el:
;;   ((nil . ((bookmark-aux-file . "._aux/bookmarks.eld"))))
;;
;; All the stock commands (`bookmark-set', `bookmark-jump', `bookmark-delete',
;; `consult-bookmark', …) become context-aware with no new commands.

;;; Code:

(require 'bookmark)
(require 'seq)

;;;; Public knobs

;;;###autoload
(defvar-local bookmark-aux-file nil
  "Path of the auxiliary bookmark file for the current buffer, or nil.
A relative path is resolved by `bookmark-aux-file-resolver' (by default,
against `default-directory').  The consumer owns this variable's lifecycle;
this library only reads it.")

;; Allow .dir-locals.el to set it without a prompt.
;;;###autoload
(put 'bookmark-aux-file 'safe-local-variable
     (lambda (v) (or (null v) (stringp v))))

(defvar bookmark-aux-file-resolver nil
  "Optional function mapping a raw `bookmark-aux-file' value to an absolute path.
Called with the raw string; must return an absolute file name.  When nil,
relative values are expanded against `default-directory'.  This is the hook a
consumer uses to resolve, say, project-root-relative paths without this
library knowing anything about projects.")

(defcustom bookmark-aux-file-include-global t
  "Whether global bookmarks are shown alongside the active auxiliary ones.
When non-nil (the default) the view merges global and auxiliary bookmarks.
When nil, buffers with an active `bookmark-aux-file' show only that file's
bookmarks.  This affects presentation only; on-disk files are unchanged."
  :type 'boolean
  :group 'bookmark)

;;;; Internal state

(defconst bookmark-aux-file--prop 'baf-file
  "Record property naming the auxiliary file a bookmark belongs to.
Held in memory only; stripped before writing, so on-disk files stay in plain
stock format.")

(defvar bookmark-aux-file--loaded nil
  "Cache cell (ABS-PATH . MTIME) of the auxiliary file currently merged in.")

(defvar bookmark-aux-file--syncing nil
  "Reentrancy guard for `bookmark-aux-file--sync'.")

(defvar bookmark-aux-file--read-count 0
  "Count of auxiliary-file reads.  For tests and diagnostics.")

;;;; Helpers

(defun bookmark-aux-file--resolve (raw)
  "Resolve RAW to an absolute path, or nil when RAW is empty/nil."
  (when (and (stringp raw) (not (string= raw "")))
    (if bookmark-aux-file-resolver
        (funcall bookmark-aux-file-resolver raw)
      (expand-file-name raw))))

(defun bookmark-aux-file--desired ()
  "Resolved auxiliary file for the current buffer, or nil."
  (bookmark-aux-file--resolve bookmark-aux-file))

(defun bookmark-aux-file--mtime (path)
  "Modification time of PATH, or nil if it does not exist."
  (when (file-exists-p path)
    (file-attribute-modification-time (file-attributes path))))

(defun bookmark-aux-file--mtime= (a b)
  "Non-nil when mtimes A and B are equal, treating two nils (absent) as equal."
  (or (and (null a) (null b))
      (and a b (time-equal-p a b))))

(defun bookmark-aux-file--tagged-p (record)
  "Return the auxiliary path RECORD belongs to, or nil."
  (bookmark-prop-get record bookmark-aux-file--prop))

(defun bookmark-aux-file--read-file (path)
  "Read bookmark records from PATH, tagging each with PATH.
Return a list of records, or nil if PATH is unreadable or malformed."
  (when (file-readable-p path)
    (setq bookmark-aux-file--read-count (1+ bookmark-aux-file--read-count))
    (let ((records
           (condition-case err
               (with-temp-buffer
                 (insert-file-contents path)
                 (goto-char (point-min))
                 (bookmark-alist-from-buffer))
             (error
              (message "bookmark-aux-file: cannot parse %s: %s"
                       path (error-message-string err))
              nil))))
      (dolist (r records records)
        (bookmark-prop-set r bookmark-aux-file--prop path)))))

(defun bookmark-aux-file--strip-tags (records)
  "Return copies of RECORDS with the auxiliary tag removed.
Does not mutate the live records, so in-memory tags survive a write."
  (mapcar (lambda (r)
            (cons (car r)
                  (assq-delete-all bookmark-aux-file--prop
                                   (copy-sequence (cdr r)))))
          records))

(defun bookmark-aux-file--view (alist)
  "Return the presentation view of ALIST.
With `bookmark-aux-file-include-global' nil and an auxiliary file active in the
current buffer, keep only the auxiliary entries; otherwise return ALIST
unchanged.  Duplicate names are intentionally NOT removed: two bookmarks that
share a name but point at different places are distinct, and collapsing them is
the user's decision (rename one), never something this library does silently --
matching stock `bookmark.el', which keeps duplicate names too."
  (if (and (not bookmark-aux-file-include-global)
           (bookmark-aux-file--desired))
      (seq-filter #'bookmark-aux-file--tagged-p alist)
    alist))

;;;; Advice bodies

(defun bookmark-aux-file--sync (&rest _)
  "Reconcile `bookmark-alist' with the current buffer's auxiliary file.
Advice :after `bookmark-maybe-load-default-file', the universal entry choke
point.  Re-reads only when the desired file or its mtime changed, so a freshly
set-but-unsaved auxiliary bookmark is never dropped."
  (unless bookmark-aux-file--syncing
    (let ((bookmark-aux-file--syncing t)
          (desired (bookmark-aux-file--desired)))
      (unless (and desired
                   (equal desired (car bookmark-aux-file--loaded))
                   (bookmark-aux-file--mtime= (bookmark-aux-file--mtime desired)
                                              (cdr bookmark-aux-file--loaded)))
        ;; (Re)build the merge: drop all auxiliary records, then re-merge.
        (setq bookmark-alist
              (seq-remove #'bookmark-aux-file--tagged-p bookmark-alist))
        (if (and desired (file-readable-p desired))
            (let ((extras (bookmark-aux-file--read-file desired)))
              (setq bookmark-alist (append extras bookmark-alist)
                    bookmark-aux-file--loaded
                    (cons desired (bookmark-aux-file--mtime desired))))
          (setq bookmark-aux-file--loaded (and desired (cons desired nil))))))))

(defun bookmark-aux-file--tag-args (args)
  "Tag and re-target ARGS of `bookmark-store' before it saves.
ARGS is (NAME ALIST NO-OVERWRITE).  Using :filter-args (not :after) so the
changes are present for `bookmark-store's own `bookmark-save-flag' write.

When an auxiliary file is active in the originating buffer we (a) stamp the
record with the auxiliary path, and (b) confine `bookmark-store's
overwrite-by-name to *auxiliary* records: if no auxiliary record of this name
exists we force the push path (NO-OVERWRITE t) so a set creates a fresh
auxiliary bookmark instead of clobbering a same-named global one.  Net effect:
while the mode is on, a set from an auxiliary buffer always targets the
auxiliary file and never touches global bookmarks.  Auxiliary records are
merged at the front, so when one of this name does exist it is the first match
and gets overwritten as usual."
  (let* ((buf (or bookmark-current-buffer (current-buffer)))
         (path (and (buffer-live-p buf)
                    (with-current-buffer buf (bookmark-aux-file--desired)))))
    (if path
        (let* ((name (nth 0 args))
               (alist (nth 1 args))
               (no-overwrite (nth 2 args))
               (bare (substring-no-properties name))
               (aux-exists
                (seq-find (lambda (r)
                            (and (equal (car r) bare)
                                 (equal (bookmark-aux-file--tagged-p r) path)))
                          bookmark-alist)))
          (list name
                (cons (cons bookmark-aux-file--prop path)
                      (assq-delete-all bookmark-aux-file--prop
                                       (copy-sequence alist)))
                (or no-overwrite (not aux-exists))))
      args)))

(defun bookmark-aux-file--partition-write (orig file)
  "Write each auxiliary group to its own file; the rest to FILE.
Advice :around `bookmark-write-file' (the sole save choke point).  Reuses
ORIG per group so all of stock's encoding logic applies, after stripping the
in-memory tag so files stay in plain stock format."
  (let ((groups nil))                   ; alist of (PATH-or-nil . records)
    (dolist (r bookmark-alist)
      (let* ((key (bookmark-aux-file--tagged-p r))
             (cell (assoc key groups)))
        (if cell (push r (cdr cell))
          (push (list key r) groups))))
    ;; Always write the global target FILE, matching stock `bookmark-write-file'
    ;; (so a global-only `bookmark-delete-all' empties it instead of leaving it
    ;; stale), and always rewrite the active auxiliary file for the same reason.
    (unless (assoc nil groups)
      (push (list nil) groups))
    (let ((cur (car bookmark-aux-file--loaded)))
      (when (and cur (not (assoc cur groups)))
        (push (list cur) groups)))
    (dolist (cell groups)
      (let* ((key (car cell))
             (target (or key file))
             (bookmark-alist (bookmark-aux-file--strip-tags (nreverse (cdr cell)))))
        ;; Create the parent directory so an auxiliary path pointing into a
        ;; not-yet-existing subdir (e.g. "._aux/bookmarks.eld") just works.
        (let ((dir (file-name-directory target)))
          (when dir (make-directory dir t)))
        (funcall orig target)
        ;; Refresh the cache so `bookmark-aux-file--sync' won't self-reload.
        (when (and key (equal key (car bookmark-aux-file--loaded)))
          (setq bookmark-aux-file--loaded
                (cons key (bookmark-aux-file--mtime key))))))))

(defun bookmark-aux-file--present (orig &rest args)
  "Advice :around readers; present the merged (optionally aux-only) view.
Reconcile the real `bookmark-alist' first so the cache is fresh; the reader's
own `bookmark-maybe-load-default-file' then re-syncs as a no-op against the
temporary view binding instead of corrupting it.  In the default merge view
this binding is the real list unchanged; it only differs when
`bookmark-aux-file-include-global' is nil."
  (bookmark-aux-file--sync)
  (let ((bookmark-alist (bookmark-aux-file--view bookmark-alist)))
    (apply orig args)))

(defun bookmark-aux-file--invalidate (&rest _)
  "Advice :after `bookmark-load'; force the next sync to rebuild the merge.
`bookmark-load' (notably the watch-reload path) can wholesale-replace
`bookmark-alist', wiping merged auxiliaries."
  (setq bookmark-aux-file--loaded nil))

(defun bookmark-aux-file--bmenu-inherit (orig &rest args)
  "Advice :around `bookmark-bmenu-list'; carry the originating buffer's
auxiliary context into the *Bookmark List* buffer.
The list is built while the originating (e.g. project) buffer is current, so
it shows the auxiliary bookmarks; but acting on an entry (RET, delete, …) runs
in the list buffer, which is not itself in the project.  Stamping the list
buffer with the originating buffer's resolved auxiliary path (absolute, so it
is project-independent) keeps those bookmarks loaded for those actions."
  (let ((aux (bookmark-aux-file--desired)))
    (prog1 (apply orig args)
      (let ((buf (get-buffer bookmark-bmenu-buffer)))
        (when buf
          (with-current-buffer buf
            (setq-local bookmark-aux-file aux)))))))

;;;; Mode

(defconst bookmark-aux-file--advices
  '((bookmark-maybe-load-default-file :after  bookmark-aux-file--sync)
    (bookmark-store                   :filter-args bookmark-aux-file--tag-args)
    (bookmark-write-file              :around bookmark-aux-file--partition-write)
    (bookmark-completing-read         :around bookmark-aux-file--present)
    (bookmark-all-names               :around bookmark-aux-file--present)
    (bookmark-bmenu-list              :around bookmark-aux-file--bmenu-inherit)
    (bookmark-load                    :after  bookmark-aux-file--invalidate))
  "Advice specs installed/removed by `bookmark-aux-file-mode'.")

(defun bookmark-aux-file--teardown ()
  "Drop merged auxiliary records and reset the cache.
The records are already persisted to their files; removing them prevents a
later stock save from leaking them into the global file."
  (setq bookmark-alist
        (seq-remove #'bookmark-aux-file--tagged-p bookmark-alist)
        bookmark-aux-file--loaded nil))

;;;###autoload
(define-minor-mode bookmark-aux-file-mode
  "Global mode adding per-buffer auxiliary bookmark files to `bookmark.el'.
See `bookmark-aux-file'."
  :global t
  :group 'bookmark
  (if bookmark-aux-file-mode
      (pcase-dolist (`(,sym ,how ,fn) bookmark-aux-file--advices)
        (advice-add sym how fn))
    (bookmark-aux-file--teardown)
    (pcase-dolist (`(,sym ,_how ,fn) bookmark-aux-file--advices)
      (advice-remove sym fn))))

(provide 'bookmark-aux-file)
;;; bookmark-aux-file.el ends here
