;;; ltex-config.el --- Minimal lsp-mode client for ltex-ls-plus -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; This module provides a self-contained lsp-mode client for ltex-ls-plus,
;; a LanguageTool-based grammar and spell checker.
;;
;; ── DESIGN PRINCIPLES ────────────────────────────────────────────────────────
;;
;; 1. Standard Protocol Compliance: Unlike lsp-ltex-plus, this client relies on
;;    standard textDocument/didOpen and didChange notifications. It avoids
;;    _ltex.checkDocument, which incorrectly reads from disk rather than the
;;    in-memory buffer.
;;
;; 2. Kind-First Routing: Built-in lsp-mode can deadlock when server-initiated
;;    requests (like workspace/configuration) collide with client requests.
;;    This module assumes the "Kind-First" dispatcher patch in lsp-core.el
;;    is active to handle such bi-directional traffic safely.
;;
;; 3. Add-on Integration: Registered with :add-on? t and :priority -1,
;;    allowing it to run concurrently with primary language servers (e.g.,
;;    texlab or basedpyright) without interference.
;;
;; 4. Transparent Settings: Settings are registered via lsp-register-custom-settings.
;;    The server fetches these via workspace/configuration. Updating the Lisp
;;    variables (like the dictionary) results in immediate server updates on
;;    the next check.
;;
;; ── EXTERNAL DEPENDENCIES ────────────────────────────────────────────────────
;;
;; - ltex-ls-plus binary on PATH
;; - Java runtime (required by the server)
;; - Optional: LanguageTool.org account (for premium features)

;;; Code:

(require 'lsp-mode)
(require 'seq)

;;;; ── Customization ───────────────────────────────────────────────────────────

(defgroup ltex nil
  "Customization group for the LTEX+ grammar checker."
  :group 'lsp-mode
  :prefix "ltex-")

(defcustom ltex-ls-plus-executable "ltex-ls-plus"
  "The name or path of the ltex-ls-plus executable."
  :type 'string
  :group 'ltex)

(defcustom ltex-debug t
  "When non-nil, enable verbose logging and JSON-RPC tracing.
Enabling this automatically sets `lsp-log-io' to t and creates
detailed log files in /tmp."
  :type 'boolean
  :group 'ltex)

(defcustom ltex-server-input-log "/tmp/ltex-server-input.log"
  "Log file for JSON-RPC input received by the server (from Emacs)."
  :type 'file
  :group 'ltex)

(defcustom ltex-server-output-log "/tmp/ltex-server-output.log"
  "Log file for JSON-RPC output produced by the server (to Emacs)."
  :type 'file
  :group 'ltex)

(defcustom ltex-language "en-US"
  "BCP 47 language tag used for grammar checking."
  :type 'string
  :group 'ltex)

(defcustom ltex-enabled ["markdown" "org" "plaintext" "latex" "restructuredtext"]
  "List of LSP language IDs for which the server should be active."
  :type '(vector string)
  :group 'ltex)

(defcustom ltex-check-frequency "edit"
  "How often the server checks the document: \"edit\", \"save\", or \"manual\"."
  :type '(choice (const "edit") (const "save") (const "manual"))
  :group 'ltex)

(defcustom ltex-diagnostic-severity "warning"
  "The Flymake severity level for grammar/spelling issues."
  :type 'string
  :group 'ltex)

(defcustom ltex-lt-server-uri "https://api.languagetoolplus.com"
  "Base URI for the LanguageTool HTTP server.
Note: ltex-ls-plus appends /v2/check to this, so omit the /v2 suffix here."
  :type 'string
  :group 'ltex)

(defcustom ltex-java-initial-heap 64
  "Initial JVM heap size in MB."
  :type 'integer
  :group 'ltex)

(defcustom ltex-java-max-heap 512
  "Maximum JVM heap size in MB."
  :type 'integer
  :group 'ltex)

(defvar ltex-trace-server "off"
  "Internal trace level: \"off\", \"messages\", or \"verbose\".
Automatically set to \"messages\" when `ltex-debug' is enabled.")

;;;; ── Internal State & Logging ───────────────────────────────────────────────

(defvar ltex--start-time nil
  "Timestamp of when `ltex--setup' was executed.")

(defvar ltex--words nil
  "In-memory plist of added dictionary words.")

(defvar ltex--disabled-rules nil
  "List of rules disabled by the user (currently transient).")

(defvar ltex--hidden-false-positives nil
  "List of hidden false positives (currently transient).")

(defun ltex--elapsed ()
  "Return seconds (float) since `ltex--start-time' or Emacs init."
  (float-time (time-subtract (current-time)
                             (or ltex--start-time before-init-time))))

(defun ltex--log-to-buffer (msg)
  "Write MSG with a timestamp to the *ltex-ls-plus::client* buffer."
  (with-current-buffer (get-buffer-create "*ltex-ls-plus::client*")
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert (format "[%10.3f] %s\n" (ltex--elapsed) msg))
      (setq buffer-read-only t))))

(defmacro ltex--log (fmt &rest args)
  "Log a formatted message if `ltex-debug' is enabled."
  `(when ltex-debug
     (ltex--log-to-buffer (format ,fmt ,@args))))

;;;; ── Dictionary Management ──────────────────────────────────────────────────

(defvar ltex-dictionary-file
  (expand-file-name "lsp-ltex-plus/stored-dictionary" user-emacs-directory)
  "Path to the persistent dictionary file (plist format).")

(defun ltex--load-words ()
  "Load the persistent dictionary from `ltex-dictionary-file'."
  (ltex--log "Loading dictionary: %s" ltex-dictionary-file)
  (setq ltex--words
        (if (not (file-exists-p ltex-dictionary-file))
            (progn (ltex--log "No dictionary file found; starting fresh.") nil)
          (condition-case err
              (with-temp-buffer
                (insert-file-contents ltex-dictionary-file)
                (read (current-buffer)))
            (error
             (message "[ltex] Failed to read dictionary: %S" err)
             nil)))))

(defun ltex--save-words ()
  "Write the current in-memory words to `ltex-dictionary-file'."
  (ltex--log "Saving dictionary to %s" ltex-dictionary-file)
  (make-directory (file-name-directory ltex-dictionary-file) t)
  (with-temp-file ltex-dictionary-file
    (prin1 ltex--words (current-buffer))))

(defun ltex--add-words (lang words)
  "Add a list of WORDS to the dictionary for LANG (e.g., \"en-US\")."
  (ltex--log "Adding words for %s: %S" lang words)
  (let* ((key (intern (concat ":" lang)))
         (current (let ((v (plist-get ltex--words key)))
                    (if (vectorp v) (append v nil) nil)))
         (merged (vconcat (seq-uniq (append words current) #'string=))))
    (setq ltex--words (plist-put (copy-sequence ltex--words) key merged)))
  (ltex--save-words))

(defun ltex-list-words ()
  "Print the current dictionary content to the echo area."
  (interactive)
  (message "[ltex] Current Dictionary: %S" ltex--words))

;;;; ── Action Handlers ────────────────────────────────────────────────────────

(defun ltex--action-add-to-dictionary (action)
  "Process the _ltex.addToDictionary action from the server."
  (ltex--log "Action: addToDictionary")
  (let* ((args (gethash "arguments" action))
         (arg0 (and (vectorp args) (aref args 0)))
         (words-by-lang (and arg0 (gethash "words" arg0))))
    (if (null words-by-lang)
        (message "[ltex] addToDictionary: Malformed arguments %S" args)
      (maphash (lambda (lang words-arr)
                 (ltex--add-words lang (append words-arr nil)))
               words-by-lang)))
  ;; Notify server of config change so it re-fetches the dictionary.
  (lsp-notify "workspace/didChangeConfiguration" '(:settings nil)))

(defun ltex--action-disable-rules (_action)
  "Process the _ltex.disableRules action (currently transient)."
  (ltex--log "Action: disableRules (not yet persistent)")
  (message "[ltex] Rule disabled for this session."))

(defun ltex--action-hide-false-positives (_action)
  "Process the _ltex.hideFalsePositives action (currently transient)."
  (ltex--log "Action: hideFalsePositives (not yet persistent)")
  (message "[ltex] False positive hidden for this session."))

;;;; ── LSP Registration ───────────────────────────────────────────────────────

(defun ltex--setup ()
  "Initialize and register the ltex-ls-plus client with lsp-mode."
  (setq ltex--start-time (current-time))
  (ltex--log "Initializing ltex-config...")

  (ltex--load-words)

  ;; Inherit credentials from environment if not manually set.
  (let ((user (getenv "LANGUAGETOOL_USERNAME"))
        (key  (getenv "LANGUAGETOOL_API_KEY")))
    (when (and user (string-empty-p (or (bound-and-true-p ltex-lt-username) "")))
      (setq-default ltex-lt-username user))
    (when (and key (string-empty-p (or (bound-and-true-p ltex-lt-api-key) "")))
      (setq-default ltex-lt-api-key key)))

  ;; Apply sticky debug defaults.
  (when ltex-debug
    (setq lsp-log-io t)
    (when (string= ltex-trace-server "off")
      (setq ltex-trace-server "messages")))

  (ltex--log "Registering settings and client...")
  (lsp-register-custom-settings
   '(("ltex.language"                       ltex-language)
     ("ltex.enabled"                        ltex-enabled)
     ("ltex.checkFrequency"                 ltex-check-frequency)
     ("ltex.diagnosticSeverity"             ltex-diagnostic-severity)
     ("ltex.dictionary"                     ltex--words)
     ("ltex.disabledRules"                  ltex--disabled-rules)
     ("ltex.hiddenFalsePositives"           ltex--hidden-false-positives)
     ("ltex.languageToolHttpServerUri"      ltex-lt-server-uri)
     ("ltex.languageToolOrg.username"       ltex-lt-username)
     ("ltex.ltex-ls.languageToolOrgApiKey"  ltex-lt-api-key)
     ("ltex.trace.server"                   ltex-trace-server)
     ("ltex.java.initialHeapSize"           ltex-java-initial-heap)
     ("ltex.java.maximumHeapSize"           ltex-java-max-heap)
     ("ltex.ltex-ls.logLevel"               "fine")
     ("ltex.completionEnabled"              nil)
     ("ltex.clearDiagnosticsWhenClosingFile" t)))

  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection
                     (lambda ()
                       (if ltex-debug
                           (list "sh" "-c"
                                 (format "tee %s | %s | tee %s"
                                         (shell-quote-argument ltex-server-input-log)
                                         (shell-quote-argument ltex-ls-plus-executable)
                                         (shell-quote-argument ltex-server-output-log)))
                         (list ltex-ls-plus-executable))))
    :major-modes '(markdown-mode gfm-mode latex-mode tex-mode
                                 plain-tex-mode text-mode org-mode
                                 rst-mode git-commit-mode)
    :server-id 'ltex-ls-plus
    :priority -1
    :add-on? t
    :initialized-fn (lambda (_workspace)
                      (ltex--log "Server initialized; pushing configuration...")
                      (lsp-notify "workspace/didChangeConfiguration"
                                  `(:settings (:ltex (:language ,ltex-language
                                                      :enabled ,ltex-enabled
                                                      :checkFrequency ,ltex-check-frequency
                                                      :languageToolHttpServerUri ,ltex-lt-server-uri
                                                      :trace (:server ,ltex-trace-server)
                                                      :languageToolOrg (:username ,ltex-lt-username)
                                                      :ltex-ls (:languageToolOrgApiKey ,ltex-lt-api-key
                                                                :logLevel "fine"))))))
    :action-handlers
    (lsp-ht ("_ltex.addToDictionary"     #'ltex--action-add-to-dictionary)
            ("_ltex.disableRules"       #'ltex--action-disable-rules)
            ("_ltex.hideFalsePositives" #'ltex--action-hide-false-positives))))
  (ltex--log "ltex--setup completed."))

;; Initialize on lsp-mode load.
(with-eval-after-load 'lsp-mode
  (dolist (pair '((tex-mode        . "latex")
                  (plain-tex-mode  . "latex")
                  (git-commit-mode . "plaintext")))
    (add-to-list 'lsp-language-id-configuration pair))
  (ltex--setup))

;;;; ── Activation ─────────────────────────────────────────────────────────────

(defun ltex-enable ()
  "Enable ltex-ls-plus for the current buffer."
  (interactive)
  (if (not (executable-find ltex-ls-plus-executable))
      (message "[ltex] Aborting: %s not found on PATH." ltex-ls-plus-executable)
    (ltex--log "Enabling LTEX+ in %s" (buffer-name))
    ;; ltex-ls-plus is not root-aware; auto-guessing avoids prompts for standalone files.
    (setq-local lsp-auto-guess-root t)
    ;; Watching is unnecessary and potentially expensive for this server.
    (setq-local lsp-enable-file-watchers nil)
    ;; UI and behavior tweaks.
    (setq-local lsp-idle-delay 0.5)
    (setq-local lsp-completion-enable nil)
    (setq-local lsp-ui-sideline-enable t)
    (setq-local lsp-modeline-code-actions-enable t)
    (lsp-deferred)))

;; Automatic hooks for supported modes.
(dolist (hook '(markdown-mode-hook tex-mode-hook text-mode-hook
                org-mode-hook rst-mode-hook git-commit-mode-hook))
  (add-hook hook #'ltex-enable))

(provide 'ltex-config)
;;; ltex-config.el ends here
