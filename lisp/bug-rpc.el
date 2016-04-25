;;; bug-rpc.el --- rpc and BZ instance specific code
;;
;; Copyright (c) 2010-2015 bug-mode developers
;;
;; See the AUTHORS.md file for a full list:
;; https://raw.githubusercontent.com/bwachter/bug-mode/master/AUTHORS.md
;;
;; Keywords: tools
;;
;; COPYRIGHT NOTICE
;;
;; This program is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by the Free
;; Software Foundation; either version 2 of the License, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
;; for more details. http://www.gnu.org/copyleft/gpl.html
;;
;;; History:
;;
;; This file is maintained at https://github.com/bwachter/bug-mode/
;; Check the git history for details.
;;
;;; Code:

(setq bug--field-cache nil)
(setq bug--url-patch-file (format "%s/patched-url/url-http-%d.%d.el"
                                  (file-name-directory (or load-file-name (buffer-file-name)))
                                  emacs-major-version
                                  emacs-minor-version))

(defun bug--instance-to-symbolp (instance)
  "Make sure that the instance handle is symbolp; returns default instance
if instance is nil"
  (let* ( ; check if instance already is correct type, if not, check if it starts with :
          ; if it does, just convert, otherwise prepend : and assume all is fine now
          ; bug-default-instance is always assumed to be correct
         (instance (if instance
                       (cond ((symbolp instance) instance)
                             ((string-match "^:" instance) (intern instance))
                             (t (intern (concat ":" instance))))
                     bug-default-instance)))
    instance))

(defun bug--instance-property (property &optional instance)
  "Return the value for a PROPERTY of the instance INSTANCE, or the default
instance if INSTANCE is empty"
  (let* ((instance(bug--instance-to-symbolp instance))
         (property-list (plist-get bug-instance-plist instance)))
    (plist-get property-list property)))

(defun bug-rpc (method args &optional instance)
  "Send an RPC response to the given (or default) bugtracker instance and return the
parsed response as alist"
  (bug--with-patched-url
   (cond
    ((equal 'rally (bug--backend-type instance))
     (bug--rpc-rally method args instance))
    (t (bug--rpc-bz method args instance)))))

(defun bug--parse-rpc-response ()
  "Parse a JSON response from buffer and return it as alist"
  (bug--debug-log-time "RPC done")
  (goto-char 0)
  (if (re-search-forward "\n\n" nil t)
      (let ((response (json-read-from-string (decode-coding-string (buffer-substring (point) (point-max)) 'utf-8))))
        (cond
         ((equal 'rally (bug--backend-type instance))
          (bug--rpc-rally-handle-error response))
         (t (bug--rpc-bug-handle-error response))))
    (error "Failed to parse http response")))

(defun bug--get-fields (&optional instance)
  "Download fields used by this bug tracker instance or returns them from cache"
  (let* ((instance (bug--instance-to-symbolp instance))
         (fields (if (plist-get bug--field-cache instance) nil
                   (cond
                    ((equal 'rally (bug--backend-type instance))
                     (bug--rpc-rally-get-fields))
                    (t (bug-rpc "Bug.fields" '() instance)))))
         (field-hash (make-hash-table :test 'equal)))
    (if fields
        (progn
          (mapcar (lambda (field)
                    (let* ((key (cdr (assoc 'name field)))
                           (bz-mapped-field (bug--rpc-bz-map-field key)))
                      ;; workaround for missing or oddly named fields in
                      ;; Bugzillas field list
                      (if (and bz-mapped-field
                               (not (gethash bz-mapped-field field-hash)))
                          (puthash bz-mapped-field field field-hash))
                      (puthash key field field-hash)))
                  (cdr (car (cdr (car fields)))))
          (setq bug--field-cache (plist-put bug--field-cache instance field-hash))
          ))
    (plist-get bug--field-cache instance)))

(defmacro bug--with-patched-url (&rest body)
  "Try to load url-http patched for https proxy if `bug-patched-url' is
non-nil and the file patched-url/url-http-major-minor.el exists."
  `(progn
     (if (and (not (equal nil bug-patched-url))
              (file-exists-p bug--url-patch-file))
         (progn
           (message (concat "Using url from " bug--url-patch-file))
           (load-file bug--url-patch-file))
       (message "Not using patched URL, which may break proxy support"))
    ,@body))

(provide 'bug-rpc)
;;; bug-rpc.el ends here
