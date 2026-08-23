;;; create.el --- Where a new note lands and what it starts as -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `vulpea-find' on a title that matches nothing creates the note through
;; `vulpea-create', which by default writes "${timestamp}_${slug}.org" into the
;; root of the vault containing nothing but `:ID:' and `#+title:'.  The notes
;; converted from the Obsidian vault follow other conventions: the file is
;; named after its title, sits in a topic folder, opens with the date, and
;; carries `:CREATED:' and `:MODIFIED:' in the file-level property drawer,
;; beside the `:ID:'.  The second matters beyond appearance —
;; `vulpea-vault/modified-stamp.el' refreshes a `:MODIFIED:' that is already
;; there and never adds one, so a note created without it never acquires it.
;;
;; Both are properties rather than keywords because vulpea indexes the
;; property drawer and ignores arbitrary keywords: `:CREATED:' reaches the
;; database as `vulpea-note-created-at' and answers
;; `vulpea-db-query-by-created-date', while a `#+created:' line would have
;; been text only grep could reach.
;;
;; `vulpea-create-default-function' supplies those defaults.  It runs in the
;; buffer the command was invoked from, so the destination can follow from
;; context — `default-directory', whether that is the directory dired is
;; listing or the one holding the note being read.  Being somewhere in the
;; vault is taken as a statement of where the note belongs; anywhere else, and
;; the note becomes a daily one under "01 Daily notes/<year>/".
;;
;; The daily tree is the exception to following `default-directory', since its
;; subdirectory is the note's year rather than a topic.
;;
;; What the note starts as then comes from the folder — the way Obsidian's
;; Templater plugin picked a template per folder.  That mapping belongs to the
;; vault, not here, so it lives in the vault's `.dir-locals.el' as
;; `vulpea-vault-template', declared once per folder against the directory
;; keys `.dir-locals.el' already supports.  Emacs resolves the folder; nothing
;; in this file matches paths.  Absent keys fall back to what this file
;; decides, which is why an entry carries only what makes its folder differ:
;; a deeper directory key replaces the value of a shallower one outright
;; rather than merging into it.
;;
;; The date lives in the file name only.  A note in a dated folder is called
;; "<date> <title>.org" — what the migrated notes look like, and what keeps a
;; directory listing in chronological order — while `#+title:' carries the
;; bare title.  Repeating the date there only made every completion candidate,
;; backlink and heading link longer without saying anything the file name and
;; `:CREATED:' do not.  A title typed with a leading ISO date is read the same
;; way: the date files the note, the remainder titles it.
;;
;; The title reaches the file name as a `:context' value instead of being
;; spliced into the template string.  vulpea expands `%(elisp)' in a template
;; before substituting data, precisely so that data is never evaluated, and
;; that guarantee covers only the values vulpea substitutes itself.  Note the
;; directory is part of the same template string, so a folder named with
;; `%(' or `%<' would be read as a directive.

;;; Code:

(require 'rx)
(require 'vulpea-vault-scheme)
(require 'vulpea-vault-core)
(require 'vulpea-vault-modified-stamp)
(require 'vulpea-vault-directories)

(defconst vulpea-vault-dated-title-regexp
  (rx bos (group (= 4 digit)) "-" (= 2 digit) "-" (= 2 digit) " ")
  "Match a title that already opens with an ISO date, capturing its year.
Such a title is not given a second date, and files under the year it
names rather than the current one.")

;;;; What a folder's notes start as

;; `vulpea-vault-template' — what a vault declares per folder — is defined in
;; `vulpea-vault/scheme.el' along with its predicate and the keys it may carry.
;; This file supplies what a template leaves out, and turns the result into a
;; note.

(defun vulpea-vault--template (dir)
  "Return the `vulpea-vault-template' the vault declares for DIR.

Resolved from DIR rather than read out of the current buffer, even when
that buffer is dired listing DIR.  The daily-note path needs a directory
nobody is visiting, so the lookup has to exist regardless; and one that
reads `.dir-locals.el' afresh cannot go stale the way a dired buffer
made before the file was last edited would."
  (with-temp-buffer
    (setq default-directory dir)
    (hack-dir-local-variables-non-file-buffer)
    vulpea-vault-template))

;;;; Where it lands

(defun vulpea-vault--context-directory ()
  "Return the vault directory the current buffer is in, or nil.

`default-directory' throughout, which is the directory dired is listing,
the directory of the note being read, or a shell's working directory —
each of them an answer to \"where am I\" that is as good a statement of
where a new note belongs.

Nil outside the vault, where the note would land somewhere vulpea does
not index, and nil inside the attachment store, which holds attachments
rather than notes.  Nil too when no vault is open, there being no inside
to be in."
  (let ((dir (expand-file-name default-directory)))
    (and vulpea-vault-directory
         (file-in-directory-p dir vulpea-vault-directory)
         (not (file-in-directory-p dir vulpea-vault-attach-directory))
         dir)))

(defun vulpea-vault--file-base (title)
  "Return TITLE as a file name base.
Only the directory separator is rewritten: every migrated note is named
after its title verbatim, and no title in the vault contains a slash."
  (replace-regexp-in-string "/" "-" title))

(defun vulpea-vault-create-defaults (title)
  "Return `vulpea-create' defaults for a note called TITLE.
Value of `vulpea-create-default-function'; see this file's commentary.
TITLE is nil for an untitled note, which then keeps a timestamp for a
file name since there is nothing to name it after."
  (let* ((here (vulpea-vault--context-directory))
         (dated (and title (string-match vulpea-vault-dated-title-regexp title)))
         (year (if dated (match-string 1 title) (format-time-string "%Y")))
         (daily (vulpea-vault-special-directory 'daily))
         ;; A vault declaring no daily folder still has to put the note
         ;; somewhere indexed, and its root is the one directory it must have.
         ;; With no vault open there is nowhere indexed at all, which is the
         ;; one case here that cannot be worked around, only reported.
         (fallback (if daily
                       (expand-file-name (concat year "/") daily)
                     (vulpea-vault-or-error)))
         ;; Anywhere in the daily tree means the note's own year, not the year
         ;; of whichever note happened to be open: reading a 2024 daily note
         ;; must not file a note dated today under 2024.
         (dir (cond ((null here) fallback)
                    ((and daily (file-in-directory-p here daily)) fallback)
                    (t here)))
         (tpl (vulpea-vault--template dir))
         (tags (plist-get tpl :tags))
         ;; Whether today's date opens the file name — the file name only,
         ;; never `#+title:'.  Not when the folder declares otherwise, and not
         ;; when the title already opens with a date, which would date it
         ;; twice.
         (datedp (and (not dated)
                      (if (plist-member tpl :dated)
                          (plist-get tpl :dated)
                        t))))
    (append
     ;; Both stamps open at the same instant; vulpea expands `%<…>' in a
     ;; property value as it does in a template, so the format string is the
     ;; same one `modified-stamp.el' refreshes with.
     (list :properties
           (let ((now (format "%%<%s>" vulpea-vault-modified-time-format)))
             (list (cons "CREATED" now) (cons "MODIFIED" now))))
     (when-let* ((head (plist-get tpl :head)))
       (list :head head))
     (when tags (list :tags tags))
     ;; Always a body, empty when the folder declares none.  vulpea writes a
     ;; blank line before a body and nothing at all without one, and the empty
     ;; string is still a body to it — which leaves the note opening where
     ;; every imported one does, a blank line below the keywords.
     (list :body (or (plist-get tpl :body) ""))
     (if title
         (list :title title
               :file-name (expand-file-name "${fname}.org" dir)
               :context (list :fname (vulpea-vault--file-base
                                      (if datedp
                                          (concat (format-time-string "%F")
                                                  " " title)
                                        title))))
       (list :file-name (expand-file-name "${timestamp}.org" dir))))))

(setq vulpea-create-default-function #'vulpea-vault-create-defaults)

(provide 'vulpea-vault-create)
;;; create.el ends here
