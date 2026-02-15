;;; lsp-ltex-bootstrap.el --- Bootstrap ltex-ls-plus install -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Download and install ltex-ls-plus (LTEX+ Language Server) into a local cache
;; directory. This module is intended to be loaded only when the server is
;; missing.
;;

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'subr-x)
(require 'url)
(require 'url-handlers)

(defconst my--ltex-plus-github-latest-url
  "https://api.github.com/repos/ltex-plus/ltex-ls-plus/releases/latest")

(defconst my--ltex-plus-fallback-version "18.6.1"
  "Fallback LTEX+ LS version if GitHub API is unavailable.")

(defun my--ltex-plus-arch-suffix ()
  "Return platform suffix for the LTEX+ LS release archive." 
  (cond
   ((and (eq system-type 'darwin)
         (or (string-match-p "aarch64" system-configuration)
             (string-match-p "arm64" system-configuration)))
    "mac-aarch64")
   ((and (eq system-type 'darwin) (string-match-p "x86_64" system-configuration))
    "mac-x64")
   ((and (eq system-type 'gnu/linux) (string-match-p "aarch64" system-configuration))
    "linux-aarch64")
   ((eq system-type 'gnu/linux)
    "linux-x64")
   (t
    (error "Unsupported system for ltex-ls-plus: %s (%s)" system-type system-configuration))))

(defun my--read-json-from-url (url)
  "Fetch URL and return parsed JSON (alist), or nil on failure." 
  (condition-case _err
      (with-current-buffer (url-retrieve-synchronously url t t 30)
        (goto-char (point-min))
        (when (re-search-forward "^\r?$" nil t)
          (json-parse-buffer :object-type 'alist
                             :array-type 'list
                             :null-object nil
                             :false-object nil)))
    (error nil)))

(defun my--ltex-plus-latest-release ()
  "Return (VERSION . DOWNLOAD-URL) for the latest LTEX+ LS release." 
  (let* ((suffix (my--ltex-plus-arch-suffix))
         (json (my--read-json-from-url my--ltex-plus-github-latest-url))
         (tag (alist-get 'tag_name json))
         (assets (alist-get 'assets json))
         (asset-name (and tag (format "ltex-ls-plus-%s-%s.tar.gz" tag suffix)))
         (asset (when (and asset-name assets)
                  (seq-find (lambda (a)
                              (string= (alist-get 'name a) asset-name))
                            assets)))
         (url (alist-get 'browser_download_url asset)))
    (if (and tag url)
        (cons tag url)
      (let* ((ver my--ltex-plus-fallback-version)
             (fallback-url (format
                            "https://github.com/ltex-plus/ltex-ls-plus/releases/download/%s/ltex-ls-plus-%s-%s.tar.gz"
                            ver ver suffix)))
        (display-warning
         'lsp-ltex
         (format "Could not query GitHub latest release; falling back to %s" ver)
         :warning)
        (cons ver fallback-url)))))

(defun my--ltex-plus-installed-p (store)
  "Return non-nil if LTEX+ LS looks installed under STORE." 
  (let ((latest (expand-file-name "latest" store)))
    (and (file-exists-p (expand-file-name "bin/ltex-ls-plus" latest))
         (file-exists-p (expand-file-name "bin/ltex-ls" latest))
         (file-executable-p (expand-file-name "bin/ltex-ls" latest)))))

(defun my--ltex-plus-write-wrapper (latest-dir)
  "Ensure the ltex-ls wrapper exists under LATEST-DIR/bin." 
  (let* ((bin (expand-file-name "bin" latest-dir))
         (wrapper (expand-file-name "ltex-ls" bin))
         (target (expand-file-name "ltex-ls-plus" bin)))
    (unless (file-executable-p target)
      (error "Missing ltex-ls-plus executable: %s" target))
    (unless (file-directory-p bin)
      (make-directory bin t))
    (with-temp-file wrapper
      (insert "#!/usr/bin/env sh\n\n")
      (insert "exec \"$(dirname \"$0\")/ltex-ls-plus\" \"$@\"\n"))
    (set-file-modes wrapper #o755)
    wrapper))

(defun my-ltex-plus-bootstrap-install (&optional store force)
  "Install LTEX+ LS into STORE.

When FORCE is non-nil, re-download and re-install." 
  (interactive)
  (let* ((store (or store (error "STORE is required")))
         (latest (expand-file-name "latest" store))
         (tar (executable-find "tar"))
         (release (my--ltex-plus-latest-release))
         (ver (car release))
         (dl (cdr release))
         (suffix (my--ltex-plus-arch-suffix))
         (archive (expand-file-name (format "ltex-ls-plus-%s-%s.tar.gz" ver suffix) store))
         (extract-dir (expand-file-name (format "ltex-ls-plus-%s" ver) store)))
    (unless tar
      (error "tar not found on PATH"))
    (make-directory store t)
    (when (and (not force) (my--ltex-plus-installed-p store))
      (message "[ltex] ltex-ls-plus already installed: %s" latest)
      (cl-return-from my-ltex-plus-bootstrap-install t))
    (message "[ltex] Installing ltex-ls-plus %s..." ver)
    (when (file-directory-p extract-dir)
      (delete-directory extract-dir t))
    (when (and force (file-exists-p archive))
      (delete-file archive))
    (unless (file-exists-p archive)
      (message "[ltex] Downloading %s" dl)
      (url-copy-file dl archive t))
    (let ((exit (call-process tar nil nil nil "-xzf" archive "-C" store)))
      (unless (and (integerp exit) (= exit 0))
        (error "Failed to extract %s (exit=%s)" archive exit)))
    (when (file-directory-p latest)
      (delete-directory latest t))
    (rename-file extract-dir latest t)
    (my--ltex-plus-write-wrapper latest)
    (message "[ltex] Installed ltex-ls-plus %s at %s" ver latest)
    t))

(defun my-ltex-plus-bootstrap-ensure-installed (store)
  "Ensure LTEX+ LS is installed in STORE; return non-nil on success." 
  (if (my--ltex-plus-installed-p store)
      t
    (condition-case err
        (my-ltex-plus-bootstrap-install store)
      (error
       (display-warning 'lsp-ltex (format "Failed to install ltex-ls-plus: %S" err) :error)
       nil))))

(provide 'lsp-ltex-bootstrap)

;;; lsp-ltex-bootstrap.el ends here
