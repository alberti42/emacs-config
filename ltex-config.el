;;; ltex-config.el --- Minimal lsp-mode client for ltex-ls-plus -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Direct lsp-mode client for ltex-ls-plus. Does NOT depend on lsp-ltex-plus.
;;
;; Design, based on manual LSP protocol tests:
;;
;; - textDocument/didOpen and textDocument/didChange trigger checking
;;   automatically. No custom scheduling needed.
;; - Before every check the server sends workspace/configuration; lsp-mode
;;   responds via lsp-register-custom-settings. This is what delivers the
;;   language, API credentials, and dictionary to the server.
;; - _ltex.checkDocument reads from disk, not from the LSP in-memory buffer.
;;   It fails on unsaved files. We never call it.
;; - _ltex.addToDictionary / _ltex.disableRules / _ltex.hideFalsePositives
;;   are handled entirely client-side via lsp action-handlers. The server
;;   never receives these commands. After updating the dictionary we notify
;;   the server via workspace/didChangeConfiguration so it re-fetches
;;   settings and immediately re-checks the document.
;;
;; The dictionary file format is compatible with lsp-ltex-plus for easy
;; migration of existing word lists.

;;; Code:

;;;; ── Debug logging ───────────────────────────────────────────────────────────

(defvar ltex-debug nil
  "When non-nil, emit verbose [ltex] messages to *Messages* and *lsp-log*.")

(defmacro ltex--log (fmt &rest args)
  "Log FMT with ARGS to *Messages* when `ltex-debug' is non-nil."
  `(when ltex-debug
     (message (concat "[ltex] " ,fmt) ,@args)))

;;;; ── Dictionary ──────────────────────────────────────────────────────────────

(defvar ltex-dictionary-file
  (expand-file-name "lsp-ltex-plus/stored-dictionary" user-emacs-directory)
  "File storing words added via 'Add to dictionary'.
Elisp plist: (:en-US [\"word1\" \"word2\"] :de-DE [\"word\" ...])")

(defvar ltex--words nil
  "In-memory plist of added words, kept in sync with `ltex-dictionary-file'.")

(defun ltex--load-words ()
  "Load words from `ltex-dictionary-file' into `ltex--words'."
  (ltex--log "loading dictionary from %s" ltex-dictionary-file)
  (setq ltex--words
        (if (not (file-exists-p ltex-dictionary-file))
            (progn (ltex--log "dictionary file does not exist — starting empty")
                   nil)
          (condition-case err
              (with-temp-buffer
                (insert-file-contents ltex-dictionary-file)
                (let ((result (read (current-buffer))))
                  (ltex--log "loaded words: %S" result)
                  result))
            (error
             (message "[ltex] Could not read dictionary %s: %S"
                      ltex-dictionary-file err)
             nil)))))

(defun ltex--save-words ()
  "Persist `ltex--words' to `ltex-dictionary-file'."
  (ltex--log "saving words to %s: %S" ltex-dictionary-file ltex--words)
  (make-directory (file-name-directory ltex-dictionary-file) t)
  (with-temp-file ltex-dictionary-file
    (prin1 ltex--words (current-buffer))))

(defun ltex--add-words (lang words)
  "Add WORDS (list of strings) to the dictionary for LANG (e.g. \"en-US\").
Deduplicates and persists immediately."
  (ltex--log "adding words for %s: %S" lang words)
  (let* ((key (intern (concat ":" lang)))
         (current (let ((v (plist-get ltex--words key)))
                    (if (vectorp v) (append v nil) nil)))
         (merged (vconcat (seq-uniq (append words current) #'string=))))
    (setq ltex--words (plist-put (copy-sequence ltex--words) key merged)))
  (ltex--log "ltex--words after add: %S" ltex--words)
  (ltex--save-words))

(defun ltex-list-words ()
  "Display all words in the dictionary."
  (interactive)
  (message "[ltex] Dictionary: %S" ltex--words))

;;;; ── Settings ────────────────────────────────────────────────────────────────

(defvar ltex-language "en-US"
  "BCP 47 language tag for grammar checking.")
(defvar ltex-enabled ["markdown" "org" "plaintext" "latex" "restructuredtext"]
  "Language IDs for which ltex-ls-plus is active.")
(defvar ltex-check-frequency "edit"
  "When to check: \"edit\", \"save\", or \"manual\".")
(defvar ltex-diagnostic-severity "warning")
(defvar ltex-java-initial-heap 64)
(defvar ltex-java-max-heap 512)
;; Empty string = use the bundled LanguageTool Java library (recommended).
;; The bundled interface handles timeouts and errors internally; setting this
;; to an HTTP URI forces LanguageToolHttpInterface which has no read timeout
;; and will hang the server's single-thread executor indefinitely on a stalled
;; connection.  Premium credentials (username/apiKey) still work via the
;; bundled interface.
(defvar ltex-lt-server-uri "")
(defvar ltex-lt-username "")
(defvar ltex-lt-api-key "")
(defvar ltex--disabled-rules nil)
(defvar ltex--hidden-false-positives nil)

;;;; ── Action handlers (client-side, no server round-trip) ────────────────────

(defun ltex--action-add-to-dictionary (action)
  "Handle _ltex.addToDictionary: persist word and refresh server config."
  (ltex--log "action: addToDictionary raw action=%S" action)
  (let* ((args (gethash "arguments" action))
         (arg0 (and (vectorp args) (aref args 0)))
         (words-by-lang (and arg0 (gethash "words" arg0))))
    (if (null words-by-lang)
        (message "[ltex] addToDictionary: unexpected argument shape %S" args)
      (maphash (lambda (lang words-arr)
                 (ltex--log "  adding %S to %s" words-arr lang)
                 (ltex--add-words lang (append words-arr nil)))
               words-by-lang)))
  ;; Tell the server configuration changed so it re-fetches workspace/configuration
  ;; (with the updated dictionary) and immediately re-checks the document.
  (ltex--log "notifying server: workspace/didChangeConfiguration")
  (lsp-notify "workspace/didChangeConfiguration" '(:settings nil)))

(defun ltex--action-disable-rules (_action)
  "Handle _ltex.disableRules (not yet persisted)."
  (ltex--log "action: disableRules (not persisted)")
  (message "[ltex] 'Disable rule' executed but not persisted across sessions."))

(defun ltex--action-hide-false-positives (_action)
  "Handle _ltex.hideFalsePositives (not yet persisted)."
  (ltex--log "action: hideFalsePositives (not persisted)")
  (message "[ltex] 'Hide false positive' executed but not persisted across sessions."))

;;;; ── lsp-mode registration ───────────────────────────────────────────────────

(defun ltex--setup ()
  "Register ltex-ls-plus settings and client with lsp-mode."
  (ltex--log "ltex--setup called")
  ;; Load words before registering so the symbol has a value on first
  ;; workspace/configuration response.
  (ltex--load-words)
  (setq ltex-lt-username (or (getenv "LANGUAGETOOL_USERNAME") "")
        ltex-lt-api-key  (or (getenv "LANGUAGETOOL_API_KEY")  ""))
  (ltex--log "credentials: username=%S api-key=%S"
             (if (string-empty-p ltex-lt-username) "<empty>" "<set>")
             (if (string-empty-p ltex-lt-api-key)  "<empty>" "<set>"))
  (ltex--log "registering custom settings")
  (ltex--log "  ltex.language=%S" ltex-language)
  (ltex--log "  ltex.enabled=%S" ltex-enabled)
  (ltex--log "  ltex.checkFrequency=%S" ltex-check-frequency)
  (ltex--log "  ltex.dictionary=%S" ltex--words)
  (ltex--log "  ltex.languageToolHttpServerUri=%S" ltex-lt-server-uri)

  (lsp-register-custom-settings
   '(("ltex.language"                    ltex-language)
     ("ltex.enabled"                     ltex-enabled)
     ("ltex.checkFrequency"              ltex-check-frequency)
     ("ltex.diagnosticSeverity"          ltex-diagnostic-severity)
     ("ltex.dictionary"                  ltex--words)
     ("ltex.disabledRules"               ltex--disabled-rules)
     ("ltex.hiddenFalsePositives"        ltex--hidden-false-positives)
     ("ltex.languageToolHttpServerUri"   ltex-lt-server-uri)
     ("ltex.languageToolOrg.username"    ltex-lt-username)
     ("ltex.languageToolOrg.apiKey"      ltex-lt-api-key)
     ("ltex.java.initialHeapSize"        ltex-java-initial-heap)
     ("ltex.java.maximumHeapSize"        ltex-java-max-heap)))

  (ltex--log "registering lsp client ltex-ls-plus")
  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection "ltex-ls-plus")
    :major-modes '(markdown-mode gfm-mode
                   latex-mode tex-mode plain-tex-mode
                   text-mode org-mode rst-mode
                   git-commit-mode)
    :server-id 'ltex-ls-plus
    :priority -1  ; add-on: run alongside other servers (e.g. texlab)
    :add-on? t
    :action-handlers
    (lsp-ht ("_ltex.addToDictionary"     #'ltex--action-add-to-dictionary)
             ("_ltex.disableRules"       #'ltex--action-disable-rules)
             ("_ltex.hideFalsePositives" #'ltex--action-hide-false-positives))))
  (ltex--log "ltex--setup done"))

;; Advise lsp-mode's workspace/configuration handler to log what we actually
;; send back to the server. This is the most critical path to observe.
(defun ltex--log-configuration-section (section result)
  "Log the workspace/configuration response for SECTION."
  (when (and ltex-debug (stringp section) (string-prefix-p "ltex" section))
    (message "[ltex] workspace/configuration response for %S => %S" section result))
  result)

(with-eval-after-load 'lsp-mode
  ;; Language-ID overrides for modes lsp-mode doesn't map by default.
  (dolist (pair '((tex-mode        . "latex")
                  (plain-tex-mode  . "latex")
                  (git-commit-mode . "plaintext")))
    (add-to-list 'lsp-language-id-configuration pair))

  ;; Intercept lsp-configuration-section to log what lsp-mode sends back
  ;; when the server requests workspace/configuration.
  (advice-add 'lsp-configuration-section :filter-return
              (lambda (result)
                ;; We don't have the section name here, so log unconditionally
                ;; (lsp-mode doesn't pass it through to the return filter).
                (when ltex-debug
                  (message "[ltex] lsp-configuration-section result: %S" result))
                result))

  (ltex--setup))

;;;; ── Per-buffer activation ───────────────────────────────────────────────────

(defun ltex-enable ()
  "Start ltex-ls-plus in the current buffer."
  (ltex--log "ltex-enable: buffer=%S major-mode=%S file=%S"
             (buffer-name) major-mode (buffer-file-name))
  (ltex--log "  language-id for this buffer: %S"
             (if (fboundp 'lsp-buffer-language) (lsp-buffer-language) "<lsp not loaded yet>"))
  ;; Suppress lsp-mode's project-root prompt for standalone files (ltex
  ;; has no concept of a project root), and disable file watchers so
  ;; lsp-mode never scans a large directory tree for a loose file in $HOME.
  (setq-local lsp-auto-guess-root t)
  (setq-local lsp-enable-file-watchers nil)
  (ltex--log "  calling lsp-deferred")
  (lsp-deferred))

(dolist (hook '(markdown-mode-hook tex-mode-hook text-mode-hook
                org-mode-hook rst-mode-hook git-commit-mode-hook))
  (add-hook hook #'ltex-enable))

(provide 'ltex-config)
;;; ltex-config.el ends here
