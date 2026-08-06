;;; create.el --- Where a new note lands -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `vulpea-find' on a title that matches nothing creates the note through
;; `vulpea-create', which by default writes "${timestamp}_${slug}.org" into the
;; root of the vault containing nothing but `:ID:' and `#+title:'.  The notes
;; converted from the Obsidian vault follow other conventions: the file is
;; named after its title and sits in a topic folder, and it carries
;; `#+created:' and `#+modified:'.  The last one matters beyond appearance —
;; `vulpea-vault/modified-keyword.el' refreshes a `#+modified:' that is already
;; there and never adds one, so a note created without it never acquires it.
;;
;; `vulpea-create-default-function' supplies those defaults.  It runs in the
;; buffer the command was invoked from, so the destination can follow from
;; context:
;;
;; - dired listing a directory of the vault: that directory, on the reading
;;   that having navigated there already says where the note belongs;
;; - anywhere else: a daily note under "01 Daily notes/<year>/", its title
;;   prefixed with today's date the way the migrated ones carry it.
;;
;; A dired buffer outside the vault falls back to the daily note rather than
;; writing where nothing would index it, and so does one inside the attachment
;; store, which holds attachments rather than notes.
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

(defconst vulpea-vault-daily-tags '("Daily")
  "Filetags for a new daily note, matching what the migrated ones carry.")

(defconst vulpea-vault-dated-title-regexp
  (rx bos (group (= 4 digit)) "-" (= 2 digit) "-" (= 2 digit) " ")
  "Match a title that already opens with an ISO date, capturing its year.
Such a title is not prefixed with a second date, and files under the
year it names rather than the current one.")

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
  (let* ((dir (vulpea-vault--dired-directory))
         (daily (and title (null dir)))
         (dated (and title (string-match vulpea-vault-dated-title-regexp title)))
         (year (if dated (match-string 1 title) (format-time-string "%Y")))
         (title (if (and daily (not dated))
                    (concat (format-time-string "%F ") title)
                  title))
         (dir (or dir (expand-file-name (concat year "/")
                                        vulpea-vault-daily-directory))))
    (append
     (list :head (format "#+created: %%<%s>\n#+modified: %%<%s>"
                         vulpea-vault-modified-time-format
                         vulpea-vault-modified-time-format))
     (when daily (list :tags vulpea-vault-daily-tags))
     (if title
         (list :title title
               :file-name (expand-file-name "${fname}.org" dir)
               :context (list :fname (vulpea-vault--file-base title)))
       (list :file-name (expand-file-name "${timestamp}.org" dir))))))

(setq vulpea-create-default-function #'vulpea-vault-create-defaults)

(provide 'vulpea-vault-create)
;;; create.el ends here
