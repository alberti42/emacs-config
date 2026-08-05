;;; pdffile.el --- Follow pdffile: links to a local PDF -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `pdffile:' is not a registered URL scheme.  It came from an AppleScript that
;; copied a reference to the page open in Adobe Acrobat, building the markdown
;; link by concatenating the literal text "[(pdf file)](pdf" with the
;; document's `file://' URL and an optional "?page=N" — so the scheme is
;; nothing more than "pdf" glued in front of "file://", and a link reads
;;
;;   pdffile:///Users/andrea/Documents/…/Foot%20-%20Atomic%20physics.pdf?page=42
;;
;; In Obsidian a plugin consumed it.  Here it is opened in Emacs instead:
;; strip the "pdf" prefix, decode the `file://' URL, and hand the path and page
;; to `pdf-preview-open', which honours `pdf-preview-viewer' (Skim, pdf-tools
;; or the OS handler) exactly as the LaTeX and Typst previews do.
;;
;; The path must come from org's own parse rather than a regexp over the buffer
;; text: these filenames contain spaces, parentheses and commas — "…(Oxford
;; University Press, 2005).pdf" — which no naive pattern survives.

;;; Code:

(require 'ol)
(require 'url-util)
(require 'pdf-preview)

(defun vulpea-vault-pdffile-parse (path)
  "Split a `pdffile:' link PATH into (FILE . PAGE).
PATH is what org reports for the link, i.e. everything after \"pdffile:\".
PAGE is nil when the link carries no \"?page=\"."
  (let* ((query-start (string-match-p "\\?" path))
         (url (substring path 0 query-start))
         (query (and query-start (substring path (1+ query-start))))
         (file (decode-coding-string
                (url-unhex-string (string-remove-prefix "//" url))
                'utf-8))
         (page (and query
                    (string-match "page=\\([0-9]+\\)" query)
                    (string-to-number (match-string 1 query)))))
    (cons file page)))

(defun vulpea-vault-pdffile-open (path _arg)
  "Open the PDF a `pdffile:' link PATH refers to, at its page if given."
  (let ((parsed (vulpea-vault-pdffile-parse path)))
    (pdf-preview-open (car parsed) (cdr parsed))))

(org-link-set-parameters "pdffile" :follow #'vulpea-vault-pdffile-open)

(provide 'vulpea-vault-pdffile)
;;; pdffile.el ends here
