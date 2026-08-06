;;; create.el --- Where a new note lands and what it starts as -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `vulpea-find' on a title that matches nothing creates the note through
;; `vulpea-create', which by default writes "${timestamp}_${slug}.org" into the
;; root of the vault containing nothing but `:ID:' and `#+title:'.  The notes
;; converted from the Obsidian vault follow other conventions: the file is
;; named after its title, sits in a topic folder, opens with the date, and
;; carries `#+created:' and `#+modified:'.  The last one matters beyond
;; appearance — `vulpea-vault/modified-keyword.el' refreshes a `#+modified:'
;; that is already there and never adds one, so a note created without it
;; never acquires it.
;;
;; `vulpea-create-default-function' supplies those defaults.  It runs in the
;; buffer the command was invoked from, so the destination can follow from
;; context:
;;
;; - dired listing a directory of the vault: that directory, on the reading
;;   that having navigated there already says where the note belongs;
;; - anywhere else: a daily note under "01 Daily notes/<year>/".
;;
;; A dired buffer outside the vault falls back to the daily note rather than
;; writing where nothing would index it, and so does one inside the attachment
;; store, which holds attachments rather than notes.
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
;; The title reaches the file name as a `:context' value instead of being
;; spliced into the template string.  vulpea expands `%(elisp)' in a template
;; before substituting data, precisely so that data is never evaluated, and
;; that guarantee covers only the values vulpea substitutes itself.  Note the
;; directory is part of the same template string, so a folder named with
;; `%(' or `%<' would be read as a directive.

;;; Code:

(require 'rx)
(require 'vulpea-vault-modified-keyword)

(defconst vulpea-vault-daily-directory
  (expand-file-name "01 Daily notes/" vulpea-config-notes-directory)
  "Root of the dated notes, one subdirectory per year.")

(defconst vulpea-vault-dated-title-regexp
  (rx bos (group (= 4 digit)) "-" (= 2 digit) "-" (= 2 digit) " ")
  "Match a title that already opens with an ISO date, capturing its year.
Such a title is not given a second date, and files under the year it
names rather than the current one.")

;;;; What a folder's notes start as

(defvar-local vulpea-vault-template nil
  "What a note created in this directory starts as, or nil for the defaults.

A plist, meant to be set per folder from the vault's `.dir-locals.el'
using its directory keys.  Keys, all optional:

  :tags   list of filetags
  :head   keywords added after `#+created:' and `#+modified:'
  :body   initial content, written a blank line below the keywords
  :dated  nil to leave the title alone; otherwise today's date opens it

An entry carries only what makes its folder differ.  Emacs replaces the
value of a shallower directory key rather than merging into it, so a
subfolder cannot inherit half of its parent's — what is absent comes
from `vulpea-vault-create-defaults' instead.")

(defconst vulpea-vault-template-keys '(:tags :head :body :dated)
  "The keys `vulpea-vault-template' may carry.")

(defun vulpea-vault-template-p (value)
  "Return non-nil if VALUE is a well-formed `vulpea-vault-template'.

Admits inert data only — strings, lists of strings, and t or nil — and
in particular no function symbols, so a vault's `.dir-locals.el' can
describe its folders without being able to introduce code."
  (and (listp value)
       (zerop (% (length value) 2))
       (let ((rest value) (ok t))
         (while (and ok rest)
           (let ((key (pop rest))
                 (val (pop rest)))
             (setq ok (pcase key
                        (:tags (and (listp val) (seq-every-p #'stringp val)))
                        ((or :head :body) (stringp val))
                        (:dated (or (eq val t) (null val)))
                        (_ nil)))))
         ok)))

(put 'vulpea-vault-template 'safe-local-variable #'vulpea-vault-template-p)

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

(defun vulpea-vault--dired-directory ()
  "Return the vault directory dired is listing, or nil.
Nil outside dired, outside the vault — where the note would land
somewhere vulpea does not index — and inside the attachment store."
  (when (derived-mode-p 'dired-mode)
    (let ((dir (expand-file-name default-directory)))
      (and (file-in-directory-p dir vulpea-config-notes-directory)
           (not (file-in-directory-p dir vulpea-config-attach-directory))
           dir))))

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
  (let* ((dired-dir (vulpea-vault--dired-directory))
         (dated (and title (string-match vulpea-vault-dated-title-regexp title)))
         (year (if dated (match-string 1 title) (format-time-string "%Y")))
         (dir (or dired-dir
                  (expand-file-name (concat year "/") vulpea-vault-daily-directory)))
         (tpl (vulpea-vault--template dir))
         (tags (plist-get tpl :tags))
         (title (if (and title (not dated)
                         (if (plist-member tpl :dated)
                             (plist-get tpl :dated)
                           t))
                    (concat (format-time-string "%F ") title)
                  title)))
    (append
     (list :head (string-join
                  (delq nil (list (format "#+created: %%<%s>\n#+modified: %%<%s>"
                                          vulpea-vault-modified-time-format
                                          vulpea-vault-modified-time-format)
                                  (plist-get tpl :head)))
                  "\n"))
     (when tags (list :tags tags))
     ;; Always a body, empty when the folder declares none.  vulpea writes a
     ;; blank line before a body and nothing at all without one, and the empty
     ;; string is still a body to it — which leaves the note opening where
     ;; every imported one does, a blank line below the keywords.
     (list :body (or (plist-get tpl :body) ""))
     (if title
         (list :title title
               :file-name (expand-file-name "${fname}.org" dir)
               :context (list :fname (vulpea-vault--file-base title)))
       (list :file-name (expand-file-name "${timestamp}.org" dir))))))

(setq vulpea-create-default-function #'vulpea-vault-create-defaults)

(provide 'vulpea-vault-create)
;;; create.el ends here
