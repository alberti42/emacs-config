;;; ltex-config.el --- Minimal lsp-mode client for ltex-ls-plus -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Direct lsp-mode client for ltex-ls-plus. Does NOT depend on lsp-ltex-plus.
;;
;; Logic aligned with working Sublime Text client:
;; - Full settings block matching Sublime's trace.
;; - Proactive configuration push on initialization.
;; - Native lsp-mode dispatcher (patched in lsp-core.el) handles bi-directional
;;   traffic robustly via Kind-First routing.

;;; Code:

;;;; ── Debug logging ───────────────────────────────────────────────────────────

(defvar ltex-debug t
  "When non-nil, emit verbose [ltex] messages to `*ltex-ls-plus::client*'.")

(defvar ltex-server-input-log "/tmp/ltex-server-input.log"
  "Log file for input received by the server (commands from Emacs).")

(defvar ltex-server-output-log "/tmp/ltex-server-output.log"
  "Log file for output produced by the server (responses to Emacs).")

(defvar ltex--start-time nil
  "Time when ltex--setup ran; used as t=0 for log timestamps.
Comparable to the server's wallClockDuration field in getServerStatus.")

(defun ltex--elapsed ()
  "Seconds with millisecond precision since `ltex--start-time' (or Emacs start)."
  (float-time (time-subtract (current-time)
                             (or ltex--start-time before-init-time))))

(defun ltex--log-to-buffer (msg)
  "Append MSG with elapsed timestamp to `*ltex-ls-plus::client*'."
  (with-current-buffer (get-buffer-create "*ltex-ls-plus::client*")
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert (format "[%10.3f] %s\n" (ltex--elapsed) msg))
      (setq buffer-read-only t))))

(defmacro ltex--log (fmt &rest args)
  "Log FMT with ARGS to `*ltex-ls-plus::client*' when `ltex-debug' is non-nil."
  `(when ltex-debug
     (ltex--log-to-buffer (format ,fmt ,@args))))

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
(defvar ltex-sentence-cache-size 2000)
(defvar ltex-java-initial-heap 64)
(defvar ltex-java-max-heap 512)
;; ltex-ls-plus appends /v2/check to this URI, so omit the /v2 suffix.
(defvar ltex-lt-server-uri "https://api.languagetoolplus.com")
(defvar ltex-lt-username "")
(defvar ltex-lt-api-key "")
(defvar ltex--disabled-rules nil)
(defvar ltex--hidden-false-positives nil)
(defvar ltex-trace-server "off")

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
  (setq ltex--start-time (current-time))
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
     ("ltex.sentenceCacheSize"           ltex-sentence-cache-size)
     ("ltex.dictionary"                  ltex--words)
     ("ltex.disabledRules"               ltex--disabled-rules)
     ("ltex.hiddenFalsePositives"        ltex--hidden-false-positives)
     ("ltex.languageToolHttpServerUri"   ltex-lt-server-uri)
     ("ltex.languageToolOrg.username"    ltex-lt-username)
     ("ltex.ltex-ls.languageToolOrgApiKey" ltex-lt-api-key)
     ("ltex.completionEnabled"           nil)
     ("ltex.ltex-ls.logLevel"            "fine")
     ("ltex.trace.server"                ltex-trace-server)
     ("ltex.java.initialHeapSize"        ltex-java-initial-heap)
     ("ltex.java.maximumHeapSize"        ltex-java-max-heap)
     ;; Missing fields to satisfy server requests
     ("ltex.additionalRules.languageModel" "")
     ("ltex.additionalRules.motherTongue"  "")
     ("ltex.additionalRules.neuralNetworkModel" "")
     ("ltex.additionalRules.word2VecModel" "")
     ("ltex.clearDiagnosticsWhenClosingFile" t)))

  (ltex--log "registering lsp client ltex-ls-plus")
  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection
                     (lambda ()
                       (if ltex-debug
                           (list "sh" "-c"
                                 (format "tee %s | ltex-ls-plus | tee %s"
                                         (shell-quote-argument ltex-server-input-log)
                                         (shell-quote-argument ltex-server-output-log)))
                         '("ltex-ls-plus"))))
    :major-modes '(markdown-mode gfm-mode
                                 latex-mode tex-mode plain-tex-mode
                                 text-mode org-mode rst-mode
                                 git-commit-mode)
    :server-id 'ltex-ls-plus
    :priority -1
    :add-on? t
    :initialized-fn (lambda (_workspace)
                      (ltex--log "initialized: pushing configuration")
                      (lsp-notify "workspace/didChangeConfiguration"
                                  `(:settings (:ltex (:language ,ltex-language
                                                                :enabled ,ltex-enabled
                                                                :checkFrequency ,ltex-check-frequency
                                                                :languageToolHttpServerUri ,ltex-lt-server-uri
                                                                :languageToolOrg (:username ,ltex-lt-username)
                                                                :ltex-ls (:languageToolOrgApiKey ,ltex-lt-api-key
                                                                                                 :logLevel "fine"))))))
    :action-handlers
    (lsp-ht ("_ltex.addToDictionary"     #'ltex--action-add-to-dictionary)
            ("_ltex.disableRules"       #'ltex--action-disable-rules)
            ("_ltex.hideFalsePositives" #'ltex--action-hide-false-positives))))
  (ltex--log "ltex--setup done"))

(with-eval-after-load 'lsp-mode
  (dolist (pair '((tex-mode        . "latex")
                  (plain-tex-mode  . "latex")
                  (git-commit-mode . "plaintext")))
    (add-to-list 'lsp-language-id-configuration pair))

  (ltex--setup))

;;;; ── Per-buffer activation ───────────────────────────────────────────────────

(defun ltex-enable ()
  "Start ltex-ls-plus in the current buffer."
  (ltex--log "ltex-enable: buffer=%S major-mode=%S file=%S"
             (buffer-name) major-mode (buffer-file-name))
  (setq-local lsp-auto-guess-root t)
  (setq-local lsp-enable-file-watchers nil)
  ;; All features enabled; patched dispatcher in lsp-core prevents deadlocks.
  (setq-local lsp-completion-enable t)
  (setq-local lsp-idle-delay 0.5)
  (setq-local lsp-ui-sideline-enable t)
  (setq-local lsp-modeline-code-actions-enable t)
  (lsp-deferred))

(dolist (hook '(markdown-mode-hook tex-mode-hook text-mode-hook
                                   org-mode-hook rst-mode-hook git-commit-mode-hook))
  (add-hook hook #'ltex-enable))

(provide 'ltex-config)
;;; ltex-config.el ends here
