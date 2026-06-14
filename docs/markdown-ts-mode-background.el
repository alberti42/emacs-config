;;; markdown-ts-mode-background.el --- Reproduce code-block background artifacts -*- lexical-binding: t; -*-

;; Run with:
;;
;;     emacs -Q -l markdown-ts-mode-background.el
;;
;; This opens a buffer that reproduces two background-rendering
;; inconsistencies in `markdown-ts-mode' (Emacs 31, grammar v0.4.x).
;;
;; Requires the `markdown' and `markdown-inline' tree-sitter grammars.
;; If they are missing, this file installs them from the upstream recipe.

(require 'treesit)

;; --- Make sure the grammars are available (no-op if already installed) ---
(dolist (src '((markdown
                "https://github.com/tree-sitter-grammars/tree-sitter-markdown"
                "split_parser" "tree-sitter-markdown/src")
               (markdown-inline
                "https://github.com/tree-sitter-grammars/tree-sitter-markdown"
                "split_parser" "tree-sitter-markdown-inline/src")))
  (add-to-list 'treesit-language-source-alist src))
(dolist (lang '(markdown markdown-inline))
  (unless (treesit-language-available-p lang)
    (treesit-install-language-grammar lang)))

(require 'markdown-ts-mode)

;; --- Theme ---
;; I run modus-operandi.  In my setup the modus palette paints code-block
;; backgrounds at #f2f2f2.  The built-in modus-operandi does not theme the
;; `markdown-ts-*' faces, so the two faces below are given that same
;; background explicitly, to keep this file self-contained under `emacs -Q'.
;;
;; Note: putting a :background on `markdown-ts-code-block' is the documented,
;; intended usage (see that face's docstring).  `markdown-ts-html-block' is
;; given a background only to expose inconsistency #1 below.
(load-theme 'modus-operandi t)
(set-face-attribute 'markdown-ts-code-block nil :background "#f2f2f2" :extend t)
(set-face-attribute 'markdown-ts-html-block nil :background "#f2f2f2" :extend t)

;; --- Sample buffer ---
(let ((buf (get-buffer-create "*markdown-ts background bug*")))
  (with-current-buffer buf
    (erase-buffer)
    (insert "Emacs LTeX+\n")
    (insert "\n")
    (insert "(example 1: HTML comments starting at column 0)\n")
    (insert "\n")
    (insert "<!-- ltex: language=en-GB -->\n")
    (insert "<!-- ltex: dictionary+=plist -->\n")
    (insert "<!-- ltex: dictionary+=defcustom -->\n")
    (insert "<!-- ltex: dictionary+=LTeX+ -->\n")
    (insert "\n")
    (insert "(example 2: the same comments, indented by 4 spaces)\n")
    (insert "\n")
    (insert "    <!-- ltex: language=en-GB -->\n")
    (insert "    <!-- ltex: dictionary+=plist -->\n")
    (insert "    <!-- ltex: dictionary+=defcustom -->\n")
    (insert "    <!-- ltex: dictionary+=LTeX+ -->\n")
    (insert "\n")
    (insert "\n")
    (insert "Regular paragraph after the indented block.\n")
    (goto-char (point-min))
    (markdown-ts-mode)
    (font-lock-ensure))
  (switch-to-buffer buf))

;; What you should see:
;;
;; Inconsistency #1 (example 1, comments at column 0)
;;   The comment text is rendered with `font-lock-comment-face' (no
;;   background, i.e. the default/white background).  But the trailing
;;   newline of each line is fontified with `markdown-ts-html-block', so
;;   the area *after* the text runs to the window edge in the code-block
;;   gray.  Text white, aftertext gray => the line looks inconsistent.
;;
;; Inconsistency #2 (example 2, indented comments)
;;   The indented block is parsed as a single `indented_code_block' node,
;;   and the node range absorbs the *trailing blank lines* after it.  Those
;;   blank lines therefore carry `markdown-ts-indented-code-block' and stay
;;   gray, so the code-block background leaks past the block into the empty
;;   lines that follow.

;;; markdown-ts-mode-background.el ends here
