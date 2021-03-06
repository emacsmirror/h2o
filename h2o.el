;;; h2o.el --- Orgmode-formatted READMEs for your ELisp

;; Copyright (C) 2009 Thomas Kappler
;; Copyright (C) 2011-2016 Puneeth Chaganti

;; Author: Puneeth Chaganti <punchagan@muse-amuse.in>
;; Created: 2011 March 20
;; Keywords: lisp, help, readme, orgmode, header, documentation, github
;; URL: <https://github.com/punchagan/h2o>

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; The git-based source code hosting site <http://github.com> has
;; lately become popular for Emacs Lisp projects. Github has a feature
;; that displays files named "README[.suffix]" automatically on a
;; project's main page. If these files are formatted in Orgmode, the
;; formatting is interpreted. See
;; <http://github.com/guides/readme-formatting> for more information.

;; Emacs Lisp files customarily have a header in a fairly standardized
;; format. h2o extracts this header, re-formats it to Orgmode,
;; and writes it to the file "README.org" in the same directory. If you
;; put your code on github, you could have this run automatically, for
;; instance upon saving the file or from a git pre-commit hook, so you
;; always have an up-to-date README on github.

;; It recognizes headings, the GPL license disclaimer which is
;; replaced by a shorter notice linking to the GNU project's license
;; website, lists, and normal paragraphs. Lists are somewhat tricky to
;; recognize automatically, and the program employs a very simple
;; heuristic currently.

;;; Dependencies:
;; None.

;;; Installation:
;; (require 'h2o), then you can call h2o-generate manually. I
;; have not found a way to call it automatically that I really like,
;; but here is one that works for me:

;;     (require 'h2o)
;;     (dir-locals-set-class-variables
;;      'generate-README-with-h2o
;;      '((emacs-lisp-mode . ((h2o-generate-readme . t)))))
;;     (dolist (dir '("~/Projects/wpmail/" "~/Projects/h2o/"))
;;       (dir-locals-set-directory-class
;;        dir 'generate-README-with-h2o))
;;     (add-hook 'after-save-hook
;;               '(lambda () (if (boundp 'h2o-generate-readme) (h2o-generate))))

;;; History:
;; 2009-11:    First release.
;; 2011-03:    Forked for Orgmode.

;;; Code:
(defun h2o-generate (&optional out-filename)
  "Generate README.org from the header of the current file."
  (interactive)
  (let ((header (h2o-extract-header))
        (filename (file-name-nondirectory (buffer-file-name))))
    (with-temp-file (or out-filename "README.org")
      (insert header)
      (insert (format "README.org generated from the library header in ~%s~ by [[https://github.com/punchagan/h2o][h2o]]\n" filename))
      (h2o-convert-header)
      (delete-trailing-whitespace))))

(defun h2o-generate-batch ()
  "Generate README.org from elisp files on the command line.
Takes two command line arguments: the elisp filename, and the target
Orgmode filename (which defaults to 'README.org'."
  (let ((in-filename (expand-file-name (or (car command-line-args-left) "")))
        (out-filename (expand-file-name (or (cadr command-line-args-left) "README.org"))))
    (message "Generating %s from %s..." out-filename in-filename)
    (with-current-buffer (find-file in-filename)
      (h2o-generate out-filename))
    (setq command-line-args-left (cddr command-line-args-left))))

(defun h2o-convert-header ()
  "Convert the header to Orgmode.
This function transforms the header in-place, so be sure to
extract the header first with h2o-extract-header and call it on
the copy."
  (goto-char (point-min))
  (h2o-find-and-replace-gpl-disclaimer)
  (while (< (line-number-at-pos) (line-number-at-pos (point-max)))
    (when (= 1 (line-number-at-pos))
      (when (re-search-forward "-\\*-.*-\\*-" (line-end-position) t)
        (replace-match ""))
      (beginning-of-line))
    (when (looking-at ";;")
      (delete-char 2)
      (cond ((looking-at "; ")  ; heading
	     (delete-char 1)
	     (if (looking-at " Code:?")
                 (delete-region (point) (line-end-position))
               (if (search-forward ".el" (line-end-position) t)
                   ;; make title and subtitle
                   (progn
                     (replace-match "")
                     (beginning-of-line)
                     (insert "#+TITLE:")
                     (when (search-forward " --- " (line-end-position) t)
                       (replace-match "\n\n")))
                 (beginning-of-line)
                 (insert "*"))
	       (progn
		 (end-of-line)
		 (backward-char)
		 (when (looking-at ":")
		   (delete-char 1)))))
	    ((h2o-looking-at-list-p) (insert "  -"))
            ((looking-at "    ") (h2o-format-code-block)) ; codeblock
	    ((looking-at " ") (delete-char 1)) ; whitespace
	    ((looking-at ";;;") ; divider
             (delete-region (point) (line-end-position))
             (insert "-----"))
            (t ()))) ; empty-line
    (forward-line 1))
    (h2o-elisp-reference-to-org-verbatim))

(defun h2o-extract-header ()
  "Extract the standard ELisp file header into a string."
  (buffer-substring (point-min) (h2o-end-of-header)))

(defun h2o-format-code-block ()
  "Format the code block starting at point as an org src block."
  (save-excursion
    (insert ";;"))
  (let* ((start (point))
         (end (h2o-end-of-code-block))
         (code (buffer-substring start end))
         code*)
    (with-temp-buffer
      (insert (format "#+BEGIN_SRC emacs-lisp\n%s\n#+END_SRC\n" code))
      (goto-char (point-min))
      (while (search-forward ";;    " nil t)
        (replace-match ""))
      (setq code* (buffer-string)))
    (delete-region start end)
    (insert code*)))

(defun h2o-end-of-code-block ()
  "Find the end of the code-block and return its position."
  (save-excursion
    (while (or (looking-at ";;    ") (looking-at "\n"))
      (forward-line 1))
    (backward-char)
    (point)))

(defun h2o-end-of-header ()
  "Find the end of the header and return its position."
  (save-excursion
    (goto-char (point-min))
    (while (or (looking-at "\n") (looking-at ";;"))
      (forward-line 1))
    (point)))

(defun h2o-looking-at-list-p ()
  "Determine if the line we're looking should become a list item.
Requires point to be at the beginning of the line."
  (looking-at " ?[[:alnum:]-]+:"))

(defun h2o-find-and-replace-gpl-disclaimer ()
  "Find the GPL license disclaimer, and replace it with a
one-line note linked to the GPL website."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward ".* is free software" nil t)
      (let ((start-line (progn (beginning-of-line) (point)))
      	    (end-line (search-forward
      		       "If not, see <http://www.gnu.org/licenses/>."
      		       nil t))
            version later)
        (goto-char start-line)
        (save-excursion
          (if (re-search-forward "\\(version [[:digit:]]\\)" end-line t)
              (setq version (match-string 1)))
          (if (re-search-forward "any later version" end-line t)
              (setq later " or later.")
            (setq later ".")))
      	(delete-region start-line end-line)
      	(insert "Licensed under the "
                (format
                 "[[http://www.gnu.org/licenses/][GPL %s]]"
                 version)
                later)))))

(defun h2o-elisp-reference-to-org-verbatim ()
  "Convert `...' to ~...~"
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward "`\\(\\S-+\\)'" nil t)
      (replace-match "~\\1~"))))

(provide 'h2o)
;;; h2o.el ends here
