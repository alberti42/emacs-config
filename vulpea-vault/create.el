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
;; What the note starts as then comes from the folder, the way Obsidian's
;; Templater plugin picked a template per folder — the mapping in
;; `vulpea-vault-folder-templates' is that configuration, carried over.
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

(defconst vulpea-vault-teaching-tag-overrides
  '(("E4 Atom und Molekülphysik" . "E4")
    ("Experimental techniques"   . "Experimental_Techniques")
    ("Organization"              . "Teaching"))
  "Teaching subfolders whose tag is not simply their own name.")

(defun vulpea-vault-teaching-tags (subpath)
  "Return the filetags for a Teaching note in SUBPATH.
SUBPATH is relative to \"05 Teaching\".  Reproduces the rule the Obsidian
template computed: the tag is the immediate subfolder with its spaces
removed, apart from the three in `vulpea-vault-teaching-tag-overrides',
and is plain \"Teaching\" for a note sitting in the folder itself."
  (let ((sub (car (split-string (or subpath "") "/" t "\\`\\.\\'"))))
    (list (cond ((null sub) "Teaching")
                ((cdr (assoc sub vulpea-vault-teaching-tag-overrides)))
                (t (replace-regexp-in-string "[[:space:]]+" "" sub))))))

(defcustom vulpea-vault-folder-templates
  `(("01 Daily notes"       :tags ("Daily"))
    ("02 Paper writing"     :tags ("Paper")
     :body ,(concat "* References\n\n--------------\n\n"
                    "- Computer:\n- Folder references:\n- Git commit:\n\n"
                    "* Observations\n"))
    ("03 Literature review" :tags ("Literature")
     :body ,(concat "* 📘 References:\n\n--------------\n\n-\n\n"
                    "* ✏️ Observations:\n\n--------------\n\n"
                    "* 📌 Summary:\n\n--------------\n"))
    ("04 Computer related"  :tags ("Computer"))
    ("05 Teaching"          :tags vulpea-vault-teaching-tags)
    ("06 MPQ"               :tags ("Regulations" "MPQ"))
    ("07 LMU"               :tags ("Regulations" "LMU"))
    ("08 Conferences"       :tags ("Daily") :head "#+location:")
    ("09 Flashcards"        :dated nil)
    ("10 Prompts"           :tags ("Prompt") :head "#+quality:")
    ("11 Software licenses" :tags ("Software")))
  "What a new note starts as, chosen by the folder it is created in.

Carried over from the Obsidian vault's Templater configuration, which
picked a template per folder, and reconciled with what the converted
notes actually carry: \"11 Software licenses\" gains the entry it never
had in Templater (all 169 of its notes are tagged Software), \"10
Prompts\" is the folder Templater still called \"11 Prompts\", and the
Templater entry sending \"09 Flashcards\" to the daily template is
dropped, no note there having ever been tagged Daily.

Each entry is a folder relative to `vulpea-config-notes-directory'
followed by a plist.  A folder covers its subfolders, and the longest
matching folder wins.  Keys:

  :tags   list of filetags, or a function of the path below the folder
  :head   keywords added after `#+created:' and `#+modified:'
  :body   initial content
  :dated  nil to leave the title alone; otherwise today's date opens it,
          as it does in 906 of the 950 converted notes

Values are expanded by `vulpea-create', so `%(elisp)', `%<format>' and
`${title}' work in them."
  :type '(alist :key-type string :value-type plist)
  :group 'vulpea)

(defun vulpea-vault--dired-directory ()
  "Return the vault directory dired is listing, or nil.
Nil outside dired, outside the vault — where the note would land
somewhere vulpea does not index — and inside the attachment store."
  (when (derived-mode-p 'dired-mode)
    (let ((dir (expand-file-name default-directory)))
      (and (file-in-directory-p dir vulpea-config-notes-directory)
           (not (file-in-directory-p dir vulpea-config-attach-directory))
           dir))))

(defun vulpea-vault--folder-template (dir)
  "Return (PLIST . SUBPATH) from `vulpea-vault-folder-templates' for DIR.
PLIST belongs to the longest configured folder containing DIR, so a
nested entry wins over the one above it, and SUBPATH is what is left of
DIR below that folder.  Nil when no entry covers DIR."
  (let (best (best-length -1))
    (pcase-dolist (`(,folder . ,plist) vulpea-vault-folder-templates)
      (let ((root (expand-file-name folder vulpea-config-notes-directory)))
        (when (and (> (length root) best-length)
                   (file-in-directory-p dir root))
          (setq best (cons plist (file-relative-name dir root))
                best-length (length root)))))
    best))

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
  (pcase-let* ((dired-dir (vulpea-vault--dired-directory))
               (dated (and title (string-match vulpea-vault-dated-title-regexp title)))
               (year (if dated (match-string 1 title) (format-time-string "%Y")))
               (dir (or dired-dir
                        (expand-file-name (concat year "/")
                                          vulpea-vault-daily-directory)))
               (`(,tpl . ,subpath) (vulpea-vault--folder-template dir))
               (tags (plist-get tpl :tags))
               (tags (if (functionp tags) (funcall tags subpath) tags))
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
     (when (plist-get tpl :body) (list :body (plist-get tpl :body)))
     (if title
         (list :title title
               :file-name (expand-file-name "${fname}.org" dir)
               :context (list :fname (vulpea-vault--file-base title)))
       (list :file-name (expand-file-name "${timestamp}.org" dir))))))

(setq vulpea-create-default-function #'vulpea-vault-create-defaults)

(provide 'vulpea-vault-create)
;;; create.el ends here
