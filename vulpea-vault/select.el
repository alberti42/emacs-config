;;; select.el --- Dates in note selection -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; The notes imported from Obsidian carried their date twice: once in the file
;; name, which is what sorts them in dired and Finder, and once again at the
;; head of the `#+title:'.  `etc/goodies/strip-title-date.py' removed the copy
;; in the title, and the title is exactly what `vulpea-find' shows.  This puts
;; the dates back where the searching happens.
;;
;; Two different dates, because they answer two different questions and in this
;; vault they disagree — 289 notes have a `:MODIFIED:' more than 90 days after
;; their note date:
;;
;;   note date   - the day the note is about, taken from the file name.  This
;;                 is the copy the strip removed, and the file name is what it
;;                 provably matched (in every one of the 905 stripped notes),
;;                 unlike `:CREATED:', which drifted during the import.
;;   :MODIFIED:  - the day the note was last edited, refreshed on save by
;;                 modified-stamp.el.  Drives the sort, so a note touched two
;;                 weeks ago is near the top and need not be dated by hand.
;;
;; `:MODIFIED:' is read from the property rather than through
;; `vulpea-note-modified-at', which vulpea fills from file mtime at sync time:
;; the import overwrote mtime with the import date on 59 files while the
;; property kept the real time.  The property is also the only one of the two
;; that survives a git clone, git storing no mtimes.
;;
;; Both dates land in the annotation, and `vulpea-select-describe' concatenates
;; the annotation into the candidate *string* — the same way it carries tags,
;; aliases and ids — so they stay matchable: typing 2024-07 still narrows.  An
;; annotation that were only a display property would not.

;;; Code:

(require 'vulpea-note)
(require 'vulpea-select)

(defvar vulpea-vault-select-show-modified t
  "When non-nil, show `:MODIFIED:' beside the note date in completion.
The sort uses it either way; this is only about the annotation, which
carries two dates per candidate and is the more crowded of the two.")

(defun vulpea-vault-select-note-date (note)
  "Return NOTE's own date as a YYYY-MM-DD string, or nil.

Taken from the file name, which is authoritative in this vault: it
matched the date stripped from every title, whereas `:CREATED:' did not.
Falls back to `:CREATED:' for a note whose file name carries no date."
  (let ((file (file-name-nondirectory (or (vulpea-note-path note) ""))))
    (if (string-match "\\`\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" file)
        (match-string 1 file)
      (vulpea-vault-select--property-date note "CREATED"))))

(defun vulpea-vault-select-modified (note)
  "Return NOTE's `:MODIFIED:' date as a YYYY-MM-DD string, or nil."
  (vulpea-vault-select--property-date note "MODIFIED"))

(defun vulpea-vault-select--property-date (note property)
  "Return the leading YYYY-MM-DD of NOTE's PROPERTY, or nil.

PROPERTY is matched with `equal': `vulpea-note-properties' is an alist
keyed by strings, and `alist-get' compares with `eq' unless told
otherwise — which silently finds nothing for every string key.

Only the date part is kept.  The values are full ISO stamps
\(2024-10-12T20:36:25+02:00); the time of day is noise in a completion
list, and truncating rather than parsing keeps this free of any
time-zone reinterpretation."
  (let ((value (alist-get property (vulpea-note-properties note) nil nil #'equal)))
    (and (stringp value)
         (string-match "\\`\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" value)
         (match-string 1 value))))

(defun vulpea-vault-select-annotate (note)
  "Annotate NOTE with its date, its `:MODIFIED:' date, and vulpea's own.

The `:MODIFIED:' date is dropped when it is the note's own date, which
is the common case for a note written and never revisited, and repeating
it would only cost width."
  (let* ((date (vulpea-vault-select-note-date note))
         (modified (and vulpea-vault-select-show-modified
                        (vulpea-vault-select-modified note)))
         (modified (and modified (not (equal modified date))
                        (concat "\u2192 " modified)))
         (stock (vulpea-select-annotate note)))
    (concat (if date (concat " " date) "")
            (if modified (concat " " modified) "")
            (if (string-empty-p stock) "" stock))))

(defun vulpea-vault-select-sort-by-modified (candidates)
  "Sort CANDIDATES most recently modified first.

Candidates are plain strings by the time a `display-sort-function' sees
them; `vulpea-select-candidate-note' is what gets back to the note
behind one.  A candidate with no note — the free-form input naming a
note that does not exist yet — sorts last on an empty key."
  (seq-sort-by
   (lambda (candidate)
     (let ((note (vulpea-select-candidate-note candidate)))
       (or (and note (or (vulpea-vault-select-modified note)
                         (vulpea-vault-select-note-date note)))
           "")))
   #'string>
   candidates))

(setq vulpea-select-annotate-fn #'vulpea-vault-select-annotate)

;; `add-to-list' rather than `setf': the entry must not displace whatever else
;; is already registered for the category, and re-loading this file must not
;; add it twice.
(add-to-list 'completion-category-overrides
             '(vulpea-note
               (display-sort-function . vulpea-vault-select-sort-by-modified)))

(provide 'vulpea-vault-select)
;;; select.el ends here
