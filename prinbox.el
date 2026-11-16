;;; prinbox.el --- The pull requests waiting on you  -*- lexical-binding: t; -*-

;; Author: creeonix
;; Version: 0.7.0
;; Package-Requires: ((emacs "29.1"))
;; URL: https://github.com/creeonix/prinbox
;; Keywords: tools, vc

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A `tabulated-list' buffer over the `prinbox' command: the pull requests waiting on you in six sections.
;; RET opens one in the browser, `s' snoozes it until something happens on it, `u' wakes it, `g' refreshes,
;; `q' buries the buffer.  `prinbox-mode-line-mode' shows the count in the mode line.
;;
;; Install the command first (`brew install creeonix/tap/prinbox-cli', signed in with `gh auth login'), then:
;;
;;   (use-package prinbox
;;     :vc (:url "https://github.com/creeonix/prinbox" :rev :newest)
;;     :commands (prinbox prinbox-mode-line-mode))
;;
;; or (package-vc-install "https://github.com/creeonix/prinbox").  See docs/emacs.md in that repository.
;; The package reads only what the command prints: titles, logins, URLs, counts and dates, never comment text.

;;; Code:

(require 'tabulated-list)
(require 'browse-url)
(require 'iso8601)
(require 'seq)
(require 'subr-x)

(defgroup prinbox nil
  "The pull requests waiting on you, through the prinbox command."
  :group 'tools
  :prefix "prinbox-")

(defcustom prinbox-command "prinbox"
  "The prinbox executable."
  :type 'string)

(defcustom prinbox-default-owners nil
  "Owners (users or organizations) whose prefix the Repository column drops.
With (\"acme\"), acme/web shows as web; other owners keep owner/name.
`auto' drops the owner when the inbox spans exactly one owner besides
you: your own repositories, and those of other users, keep their prefix.
When nil, the defaultOwners list in $XDG_CONFIG_HOME/prinbox/settings.json
applies, if present."
  :type '(choice (const :tag "The only owner besides you" auto)
                 (repeat :tag "These owners" string))
  :package-version '(prinbox . "0.9.0")
  :group 'prinbox)

(defcustom prinbox-max-age 60
  "Serve the cache when GitHub confirmed it within this many seconds.
0 fetches now."
  :type 'integer)

(defcustom prinbox-section-column t
  "When nil, drop the Section column and let the section rules name the sections.
The first section then gets a rule too.  Rows keep their section in their data."
  :type 'boolean
  :package-version '(prinbox . "0.9.0")
  :group 'prinbox)

(defcustom prinbox-poll-seconds 0
  "Refresh this often in the background for the mode line; 0 turns polling off."
  :type 'integer)

(defcustom prinbox-review-order nil
  "Order of rows in the review sections (Needs your review and the like).
nil keeps the command's order: longest waiting first.  `recent' puts the
newest first.  `quick' puts small PRs first (up to 50, 250, 1000 changed
lines, then larger), newest first within a size.  `small-first' orders by
changed lines, smallest first."
  :type '(choice (const :tag "Longest waiting (command's order)" nil)
                 (const :tag "Newest first" recent)
                 (const :tag "Small and recent first" quick)
                 (const :tag "Smallest first" small-first))
  :package-version '(prinbox . "0.9.0")
  :group 'prinbox)

(defcustom prinbox-review-drafts 'show
  "Drafts in the review sections.
`show' keeps them in place, `last' puts them after the rest, `hide' drops them."
  :type '(choice (const show) (const last) (const hide))
  :package-version '(prinbox . "0.9.0")
  :group 'prinbox)

(defcustom prinbox-all nil
  "When non-nil, list every open pull request you reviewed in a Reviewed section.
This passes `--all' to `prinbox inbox'."
  :type 'boolean
  :group 'prinbox)

(defcustom prinbox-rows nil
  "Rows per section before \"+N more on GitHub\"; nil keeps the command's 8.
This passes `--rows' to `prinbox inbox', which takes 1 to 100."
  :type '(choice (const :tag "Command default (8)" nil) (integer :tag "Rows"))
  :package-version '(prinbox . "0.9.0")
  :group 'prinbox)

(defface prinbox-section '((t :inherit font-lock-keyword-face :weight bold))
  "The section column.")

(defface prinbox-section-needs-review '((t :inherit (font-lock-keyword-face prinbox-section)))
  "The Needs your review section.")

(defface prinbox-section-take-another-look '((t :inherit (font-lock-warning-face prinbox-section)))
  "The Take another look section.")

(defface prinbox-section-replies '((t :inherit (font-lock-function-name-face prinbox-section)))
  "The Replies to you and Mentions sections.")

(defface prinbox-section-yours '((t :inherit (font-lock-type-face prinbox-section)))
  "The Your PRs section.")

(defface prinbox-section-waiting '((t :inherit (font-lock-comment-face prinbox-section)))
  "The Waiting on others section.")

(defface prinbox-section-reviewed '((t :inherit (shadow prinbox-section)))
  "The Reviewed section.")

(defface prinbox-section-continued '((t :inherit shadow))
  "The section label on the second and later rows of a section.")

(defface prinbox-separator '((t :inherit shadow))
  "The rule between sections.")

(defconst prinbox-section-kind-faces
  '(("needsReview" . prinbox-section-needs-review)
    ("takeAnotherLook" . prinbox-section-take-another-look)
    ("repliesToYou" . prinbox-section-replies)
    ("mentions" . prinbox-section-replies)
    ("yourPRs" . prinbox-section-yours)
    ("waitingOnOthers" . prinbox-section-waiting)
    ("reviewed" . prinbox-section-reviewed))
  "A face per section kind, a ready value for `prinbox-section-faces'.")

(defcustom prinbox-section-faces nil
  "Face of each section's label, by the section's kind.
Kinds not listed use `prinbox-section'.  Nil uses it for every section;
set it to `prinbox-section-kind-faces' for a color per section."
  :type '(alist :key-type string :value-type face)
  :package-version '(prinbox . "0.9.0")
  :group 'prinbox)

(defcustom prinbox-section-separator nil
  "What goes between sections.
`rule' draws a line naming the section, `blank' a blank line, nil nothing."
  :type '(choice (const :tag "Rule with the section's title" rule)
                 (const :tag "Blank line" blank)
                 (const :tag "Nothing" nil))
  :package-version '(prinbox . "0.9.0")
  :group 'prinbox)

(defcustom prinbox-section-repeat-label 'show
  "The section label on a section's second and later rows: `show', `dim' or `hide'."
  :type '(choice (const show) (const dim) (const hide))
  :package-version '(prinbox . "0.9.0")
  :group 'prinbox)

(defface prinbox-new '((t :weight bold))
  "A row new since the last look at the popover.")

(defface prinbox-reason-failure
  '((t :inherit error :weight bold :box (:line-width (1 . -1) :style flat-button)))
  "A badge for a reason that blocks the PR.
CI is red, merge conflicts or changes requested.")

(defface prinbox-reason-attention '((t :inherit font-lock-constant-face))
  "A reason that asks something of you.
A review, a reply, or a push since your verdict.")

(defface prinbox-reason-success
  '((t :inherit success :weight bold :box (:line-width (1 . -1) :style flat-button)))
  "A badge for Ready to merge.")

(defface prinbox-reason-neutral '((t :inherit shadow))
  "A reason that waits on someone else.
A draft, waiting for review, or your own verdict.")

(defcustom prinbox-reason-badges nil
  "Non-nil colors the Reason column by tone, as the app does.
Failures and Ready to merge show as badges; nil keeps the row's face."
  :type 'boolean
  :package-version '(prinbox . "0.9.0")
  :group 'prinbox)

(defconst prinbox--reason-tones
  '(("changesRequested" . failure) ("mergeConflicts" . failure) ("ciRed" . failure)
    ("readyToMerge" . success)
    ("draft" . neutral) ("waitingForReview" . neutral) ("snoozed" . neutral)
    ("youApproved" . neutral) ("youRequestedChanges" . neutral) ("youCommented" . neutral))
  "The tone of each reason code, as `Reason.tone' in the Swift core.
Codes not listed are attention.")

(defun prinbox--reason-face (row)
  "The face of ROW's reason: a badge for failure and success, plain otherwise."
  (pcase (alist-get (alist-get 'reason row) prinbox--reason-tones 'attention nil #'equal)
    ('failure 'prinbox-reason-failure)
    ('success 'prinbox-reason-success)
    ('neutral 'prinbox-reason-neutral)
    (_ 'prinbox-reason-attention)))

(defface prinbox-snoozed '((t :inherit shadow))
  "A snoozed row.")

(defface prinbox-message '((t :inherit warning))
  "A message shown in place of rows.")

(defface prinbox-separator '((t :inherit shadow))
  "The rule between sections.")

(defcustom prinbox-icons nil
  "Icons before reasons and in section rules: nil, `unicode' or `nerd'.
`unicode' uses one-column symbols any font has.  `nerd' uses Octicons from
the nerd-icons package and needs a Nerd Font (M-x nerd-icons-install-fonts);
any icon it cannot draw falls back to `unicode'.  No images either way."
  :type '(choice (const :tag "None" nil)
                 (const :tag "Unicode symbols" unicode)
                 (const :tag "Nerd Font Octicons" nerd))
  :package-version '(prinbox . "0.9.0")
  :group 'prinbox)

(defconst prinbox--icons
  ;; code                          unicode  octicon (nerd-icons name)
  '(("reviewRequested"             "●" "nf-oct-eye")
    ("reReviewRequested"           "↺" "nf-oct-sync")
    ("mentioned"                   "@" "nf-oct-mention")
    ("awaitingReply"               "↩" "nf-oct-reply")
    ("openThreads"                 "⋯" "nf-oct-comment_discussion")
    ("changesRequested"            "±" "nf-oct-file_diff")
    ("mergeConflicts"              "⚠" "nf-oct-alert")
    ("ciRed"                       "✗" "nf-oct-x_circle")
    ("readyToMerge"                "✓" "nf-oct-check_circle")
    ("draft"                       "◌" "nf-oct-git_pull_request_draft")
    ("waitingForReview"            "○" "nf-oct-hourglass")
    ("snoozed"                     "☾" "nf-oct-moon")
    ("pushedSinceApproval"         "↻" "nf-oct-repo_push")
    ("pushedSinceChangesRequested" "↻" "nf-oct-repo_push")
    ("youApproved"                 "✓" "nf-oct-check")
    ("youRequestedChanges"         "±" "nf-oct-diff")
    ("youCommented"                "✎" "nf-oct-comment")
    ;; sections
    ("needsReview"                 "●" "nf-oct-eye")
    ("repliesToYou"                "↩" "nf-oct-reply")
    ("takeAnotherLook"             "↻" "nf-oct-sync")
    ("mentions"                    "@" "nf-oct-mention")
    ("yourPRs"                     "◆" "nf-oct-git_pull_request")
    ("waitingOnOthers"             "○" "nf-oct-hourglass")
    ("reviewed"                    "✓" "nf-oct-check"))
  "Icons by reason code or section kind: (CODE UNICODE NERD-NAME).")

(defun prinbox--icon (code)
  "The icon for CODE (a reason code or a section kind) under `prinbox-icons'.
An empty string when icons are off or CODE has none."
  (let ((entry (assoc code prinbox--icons)))
    (cond ((or (null prinbox-icons) (null entry)) "")
          ((and (eq prinbox-icons 'nerd)
                (require 'nerd-icons nil t)
                (fboundp 'nerd-icons-octicon))
           (or (ignore-errors
                 (let ((glyph (nerd-icons-octicon (nth 2 entry))))
                   (and (stringp glyph) (not (string-empty-p glyph)) glyph)))
               (nth 1 entry)))
          (t (nth 1 entry)))))

(defun prinbox--with-icon (code text)
  "TEXT with CODE's icon and a space in front, or TEXT alone without one."
  (let ((icon (prinbox--icon code)))
    (if (string-empty-p icon) text (concat icon " " text))))

(defconst prinbox--install "prinbox not found: brew install creeonix/tap/prinbox-cli"
  "What to say when the command is missing.")

(defvar prinbox--last nil
  "The last report that held a document: a plist (:document DOC :message MSG).")

(defvar prinbox--failed nil
  "Non-nil when the latest inbox run produced no document.")

(defvar-local prinbox--report nil
  "The report the buffer shows.")

(defvar prinbox--timer nil
  "The poll timer of `prinbox-mode-line-mode'.")

(defvar prinbox-mode-line-string ""
  "The count for the mode line, as `prinbox inbox --format tmux' prints it.")
(put 'prinbox-mode-line-string 'risky-local-variable t)

;;;; The command

(defun prinbox--decode (text)
  "Parse TEXT as the inbox document (an alist), or nil."
  (condition-case nil
      (let ((value (json-parse-string text :object-type 'alist :array-type 'list
                                      :null-object nil :false-object nil)))
        (and (listp value) value))
    (error nil)))

(defun prinbox--report (code stdout stderr)
  "Turn the exit CODE, STDOUT and STDERR of an inbox run into a report plist."
  (let* ((document (prinbox--decode stdout))
         (err (string-trim-right (or stderr "")))
         (version (and document (alist-get 'version document))))
    (cond
     ((and document (not (eql version 1)))
      (list :message (format "prinbox prints JSON version %s; this plugin reads version 1" version)))
     ((eql code 0)
      (if document (list :document document) (list :message "prinbox printed something that is not JSON")))
     ((eql code 1)
      (list :document document
            :message (or (alist-get 'message (alist-get 'error document)) err)))
     ((eql code 3)
      (list :document document :setup t
            :message (if (string-empty-p err) "prinbox needs setup: gh auth login" err)))
     ((eql code 127) (list :message prinbox--install))
     (t (list :message (if (string-empty-p err) (format "prinbox exited with %s" code) err))))))

(defun prinbox--process (args interpret callback)
  "Run the command with ARGS and call CALLBACK when it exits.
CALLBACK receives what INTERPRET makes of the exit code, stdout and stderr."
  (let ((stdout (generate-new-buffer " *prinbox-stdout*"))
        (stderr (generate-new-buffer " *prinbox-stderr*")))
    (condition-case nil
        (make-process
         :name "prinbox" :buffer stdout :stderr stderr :noquery t :connection-type 'pipe
         :command (cons prinbox-command args)
         :sentinel
         (lambda (process _event)
           (when (memq (process-status process) '(exit signal))
             ;; Bounded: a grandchild holding stderr open must not freeze Emacs (sentinels inhibit quit).
             (let ((errp (get-buffer-process stderr))
                   (deadline (+ (float-time) 1.0)))
               (while (and errp (process-live-p errp) (< (float-time) deadline))
                 (accept-process-output errp 0.05))
               (when (and errp (process-live-p errp))
                 (delete-process errp)))
             (let ((code (process-exit-status process))
                   (out (with-current-buffer stdout (buffer-string)))
                   (err (with-current-buffer stderr (buffer-string))))
               (kill-buffer stdout)
               (kill-buffer stderr)
               (funcall callback (funcall interpret code out err))))))
      (file-error
       (kill-buffer stdout)
       (kill-buffer stderr)
       (funcall callback (funcall interpret 127 "" ""))))))

(defun prinbox--remember (report)
  "Keep REPORT when it holds a document and refresh the mode line.
Note whether it did, for `prinbox--count'."
  (when (plist-get report :document) (setq prinbox--last report))
  (setq prinbox--failed (null (plist-get report :document)))
  (setq prinbox-mode-line-string (prinbox--count))
  (force-mode-line-update t))

(defun prinbox--inbox (args callback)
  "Run `prinbox inbox --format json' with ARGS and call CALLBACK with the report."
  (prinbox--process (append (list "inbox" "--format" "json") (and prinbox-all (list "--all"))
                            (and prinbox-rows (list "--rows" (number-to-string prinbox-rows))) args) #'prinbox--report
                    (lambda (report) (prinbox--remember report) (funcall callback report))))

(defun prinbox--count ()
  "The count as `--format tmux' spells it.
The badge, nothing when idle, `!' first after a failure: a document with an
error, or a run that printed no document (then the last known badge follows)."
  (let* ((document (plist-get prinbox--last :document))
         (badge (or (alist-get 'badge document) 0))
         (text (if (> badge 0) (number-to-string badge) "")))
    (if (or prinbox--failed (alist-get 'error document)) (concat "!" text) text)))

;;;; The buffer

(defun prinbox--rows (document)
  "Every row of DOCUMENT with its section, in display order: (SECTION . ROW)."
  (let (rows)
    (dolist (section (alist-get 'sections document))
      (dolist (row (alist-get 'rows section))
        (push (cons section row) rows)))
    (nreverse rows)))

(defvar prinbox--settings-cache nil
  "The shared settings.json as (FILE MTIME . ALIST), reread on change.")

(defun prinbox--settings-file ()
  "The settings.json the command and the app share.
It lives under the XDG config directory."
  (expand-file-name "prinbox/settings.json"
                    (or (getenv "XDG_CONFIG_HOME") (expand-file-name "~/.config"))))

(defun prinbox--setting (key)
  "KEY (a symbol) from the shared settings.json.
Nil when the key or the file is missing."
  (let* ((file (prinbox--settings-file))
         (mtime (file-attribute-modification-time (file-attributes file))))
    (when mtime
      (unless (and prinbox--settings-cache
                   (equal (car prinbox--settings-cache) file)
                   (equal (cadr prinbox--settings-cache) mtime))
        (setq prinbox--settings-cache
              (cons file (cons mtime (ignore-errors
                                       (with-temp-buffer
                                         (insert-file-contents file)
                                         (json-parse-buffer :object-type 'alist :array-type 'list)))))))
      (alist-get key (cddr prinbox--settings-cache)))))

(defvar prinbox--document-owners nil
  "The owner `auto' drops for the document being listed, as a list, or nil.")

(defun prinbox--auto-owners (document)
  "The one owner of DOCUMENT's repositories besides the viewer, as a list.
Nil when the rows span no owner or several besides the viewer."
  (let* ((viewer (alist-get 'viewer document))
         (owners (seq-uniq
                  (seq-keep (lambda (item)
                              (when-let* ((repository (alist-get 'repository (cdr item)))
                                          (slash (string-search "/" repository))
                                          (owner (substring repository 0 slash))
                                          ((not (and (stringp viewer) (string-equal-ignore-case owner viewer)))))
                                (downcase owner)))
                            (prinbox--rows document)))))
    (and (= (length owners) 1) owners)))

(defun prinbox--owners ()
  "The default owners.
The list in `prinbox-default-owners'; for `auto', the document's one owner
besides you; when nil, defaultOwners in settings.json."
  (cond ((eq prinbox-default-owners 'auto) prinbox--document-owners)
        (prinbox-default-owners)
        (t (let ((owners (prinbox--setting 'defaultOwners)))
             (and (listp owners) (seq-filter #'stringp owners))))))

(defun prinbox--short-repository (repository)
  "REPOSITORY without its owner when the owner is one of `prinbox--owners'."
  (if-let* ((slash (string-search "/" repository))
            ((member-ignore-case (substring repository 0 slash) (prinbox--owners))))
      (substring repository (1+ slash))
    repository))

(defun prinbox--flatten (text)
  "TEXT with control characters turned into spaces."
  (replace-regexp-in-string "[[:cntrl:]]+" " " (or text "")))

(defun prinbox--flags (row)
  "The flags column of ROW."
  (let ((stack (alist-get 'stack row)))
    (string-join
     (delq nil (list (and (alist-get 'isNew row) "new")
                     (and (alist-get 'isDraft row) "draft")
                     (and (alist-get 'snoozed row) "snoozed")
                     (and stack (format "stack %s/%s" (alist-get 'position stack) (alist-get 'size stack)))))
     " ")))

(defconst prinbox--review-kinds '("needsReview" "repliesToYou" "takeAnotherLook" "mentions")
  "Sections where you are the reviewer: the ones `prinbox-review-order' reorders.")

(defun prinbox--row-size (row)
  "Changed lines of ROW: additions plus deletions, 0 when unknown."
  (+ (or (alist-get 'additions row) 0) (or (alist-get 'deletions row) 0)))

(defun prinbox--size-bucket (row)
  "ROW's size bucket: 0 up to 50 lines, 1 up to 250, 2 up to 1000, else 3."
  (let ((size (prinbox--row-size row)))
    (cond ((<= size 50) 0) ((<= size 250) 1) ((<= size 1000) 2) (t 3))))

(defun prinbox--row-draft-p (row)
  "Non-nil when ROW is a draft."
  (eq (alist-get 'isDraft row) t))

(defun prinbox--waiting (row)
  "ROW's waitingSince (or updatedAt) as an ISO 8601 string; empty when absent."
  (or (alist-get 'waitingSince row) (alist-get 'updatedAt row) ""))

(defun prinbox--order-rows (section rows)
  "ROWS of SECTION, ordered for review.
The order follows `prinbox-review-order' and `prinbox-review-drafts'.
Only review sections change.  Rows of one stack stay together, in place of the
stack's first row.  With both options at their defaults, ROWS are unchanged."
  (if (not (member (alist-get 'kind section) prinbox--review-kinds))
      rows
    (let* ((rows (if (eq prinbox-review-drafts 'hide) (seq-remove #'prinbox--row-draft-p rows) rows))
           ;; Blocks: a stack's rows as one unit, any other row alone.
           (blocks (let (out current)
                     (dolist (row rows)
                       (if (and current (alist-get 'stack row) (alist-get 'stack (car (last current))))
                           (setq current (append current (list row)))
                         (when current (push current out))
                         (setq current (list row))))
                     (when current (push current out))
                     (nreverse out)))
           (key (lambda (block)
                  (let ((head (car block)))
                    (list (if (and (eq prinbox-review-drafts 'last) (prinbox--row-draft-p head)) 1 0)
                          (pcase prinbox-review-order
                            ('quick (prinbox--size-bucket head))
                            ('small-first (prinbox--row-size head))
                            (_ 0))
                          (pcase prinbox-review-order
                            ((or 'recent 'quick 'small-first) (prinbox--waiting head))
                            (_ ""))))))
           (before (lambda (a b)
                     (let ((ka (funcall key a)) (kb (funcall key b)))
                       (cond ((/= (nth 0 ka) (nth 0 kb)) (< (nth 0 ka) (nth 0 kb)))
                             ((/= (nth 1 ka) (nth 1 kb)) (< (nth 1 ka) (nth 1 kb)))
                             ;; Newest wait first; equal keys keep the CLI's order (stable sort).
                             (t (string> (nth 2 ka) (nth 2 kb))))))))
      (apply #'append (sort (copy-sequence blocks) before)))))

(defun prinbox--hhmm (iso)
  "HH:MM in local time for the ISO 8601 date ISO."
  (format-time-string "%H:%M" (encode-time (iso8601-parse iso))))

(defun prinbox--header (report)
  "The header line for REPORT."
  (let ((document (plist-get report :document))
        (message (plist-get report :message)))
    (if (not document)
        (or message "prinbox")
      (let ((parts (list (format "%d waiting on you" (or (alist-get 'badge document) 0)))))
        (when-let* ((at (alist-get 'checkedAt document)))
          (push (concat "updated " (prinbox--hhmm at)) parts))
        (when (> (or (alist-get 'newCount document) 0) 0)
          (push (format "%d new" (alist-get 'newCount document)) parts))
        (when-let* ((repositories (alist-get 'defaultRepositories document)))
          (push (string-join repositories ", ") parts))
        (when message
          (push (car (split-string message "\n")) parts))
        (string-join (nreverse parts) " · ")))))

(defun prinbox--entries (report)
  "The `tabulated-list-entries' for REPORT: the rows, or the message's lines.
The message's lines show when there are no rows, and in place of the rows
when setup is needed."
  (let* ((document (plist-get report :document))
         (rows (and document (not (plist-get report :setup)) (prinbox--rows document)))
         (prinbox--document-owners (and document (prinbox--auto-owners document)))
         entries)
    (if (and (null rows) (plist-get report :message))
        (let ((index 0))
          (dolist (line (split-string (plist-get report :message) "\n"))
            (setq index (1+ index))
            (push (list (format "message-%d" index)
                        (vector "" "" (propertize line 'face 'prinbox-message) "" "" "" ""))
                  entries)))
      (dolist (section (alist-get 'sections document))
        (let ((first t))
          (dolist (row (prinbox--order-rows section (alist-get 'rows section)))
            (push (prinbox--row-entry section row first) entries)
            (setq first nil))
          (when (> (or (alist-get 'moreCount section) 0) 0)
            (push (prinbox--more-entry section first) entries)))))
    (nreverse entries)))

(defun prinbox--section-label (section first)
  "SECTION's title for the section column; FIRST is non-nil on its first row.
The text stays the title on every row; only its face, or its display under
`prinbox-section-repeat-label' `hide', changes."
  (let ((title (alist-get 'title section)))
    (cond (first
           (propertize title 'face (or (cdr (assoc (alist-get 'kind section) prinbox-section-faces))
                                       'prinbox-section)))
          ((eq prinbox-section-repeat-label 'hide)
           (propertize title 'display (make-string (string-width title) ?\s)))
          ((eq prinbox-section-repeat-label 'dim)
           (propertize title 'face 'prinbox-section-continued))
          (t (propertize title 'face (or (cdr (assoc (alist-get 'kind section) prinbox-section-faces))
                                         'prinbox-section))))))

(defun prinbox--row-entry (section row &optional first)
  "The entry for ROW of SECTION; FIRST is non-nil on the section's first row."
  (let ((face (cond ((alist-get 'snoozed row) 'prinbox-snoozed)
                    ((alist-get 'isNew row) 'prinbox-new)
                    (t 'default))))
    (list (alist-get 'id row)
          (vector (prinbox--section-label section first)
                  (propertize (number-to-string (alist-get 'number row)) 'face face)
                  (propertize (prinbox--flatten (alist-get 'title row)) 'face face)
                  (propertize (prinbox--short-repository (alist-get 'repository row)) 'face face)
                  (propertize (prinbox--with-icon (alist-get 'reason row) (alist-get 'reasonText row))
                              'face (if (or (alist-get 'snoozed row) (not prinbox-reason-badges))
                                        face
                                      (prinbox--reason-face row)))
                  (propertize (alist-get 'age row) 'face face)
                  (prinbox--flags row)))))

(defun prinbox--more-entry (section &optional first)
  "The `+N more on GitHub' entry of the capped SECTION; FIRST when it has no rows."
  (list (format "more-%s" (alist-get 'kind section))
        (vector (prinbox--section-label section first)
                ""
                (propertize (format "+%d more on GitHub" (alist-get 'moreCount section))
                            'face 'prinbox-message)
                "" "" "" "")))

(defvar-keymap prinbox-mode-map
  :doc "Keys of `prinbox-mode'."
  :parent tabulated-list-mode-map
  "RET" #'prinbox-open
  "b" #'prinbox-open
  "s" #'prinbox-snooze
  "u" #'prinbox-unsnooze
  "g" #'prinbox-refresh
  "G" #'prinbox-refresh
  "y" #'prinbox-copy-link
  "w" #'prinbox-copy-link
  "a" #'prinbox-toggle-all
  "M-n" #'prinbox-next-section
  "M-p" #'prinbox-previous-section)

(define-derived-mode prinbox-mode tabulated-list-mode "prinbox"
  "The pull requests waiting on you."
  (let ((format [("Section" 18 nil) ("#" 6 nil :right-align t) ("Title" 48 nil) ("Repository" 20 nil)
                 ("Reason" 20 nil) ("Age" 5 nil) ("Flags" 12 nil)]))
    (setq tabulated-list-format (if prinbox-section-column format (seq-subseq format 1))))
  (setq-local tabulated-list-printer #'prinbox--print-entry)
  (setq tabulated-list-padding 1)
  (setq tabulated-list-sort-key nil)
  (setq-local revert-buffer-function #'prinbox--revert)
  ;; The column titles print as the buffer's first line: the header line holds the summary.
  (setq-local tabulated-list-use-header-line nil)
  (tabulated-list-init-header))

(defun prinbox--buffer ()
  "The *prinbox* buffer."
  (get-buffer-create "*prinbox*"))

(defun prinbox--render (report)
  "Show REPORT in the buffer."
  (with-current-buffer (prinbox--buffer)
    (unless (derived-mode-p 'prinbox-mode) (prinbox-mode))
    (setq prinbox--report report)
    (setq header-line-format (prinbox--header report))
    (setq tabulated-list-entries (prinbox--entries report))
    (tabulated-list-print t)
    (prinbox--separate-sections)))

(defun prinbox--print-entry (id cols)
  "Print the entry ID with COLS, without the Section cell when that column is off.
The line keeps the full COLS as its entry, so the section stays readable."
  (if (= (length cols) (length tabulated-list-format))
      (tabulated-list-print-entry id cols)
    (let ((start (point)))
      (tabulated-list-print-entry id (seq-subseq cols 1))
      (put-text-property start (point) 'tabulated-list-entry cols))))

(defun prinbox--section-starts ()
  "Positions of the first line of each section, in buffer order."
  (save-excursion
    (goto-char (point-min))
    (let (starts last)
      (while (not (eobp))
        (when-let* ((entry (tabulated-list-get-entry))
                    (section (substring-no-properties (aref entry 0)))
                    ((not (string-empty-p section)))
                    ((not (equal section last))))
          (push (point) starts)
          (setq last section))
        (forward-line 1))
      (nreverse starts))))

(defun prinbox--section-kind (title)
  "The kind of the section titled TITLE in the shown report, or nil."
  (alist-get 'kind (seq-find (lambda (section) (equal (alist-get 'title section) title))
                             (alist-get 'sections (plist-get prinbox--report :document)))))

(defun prinbox--separate-sections ()
  "Put `prinbox-section-separator' before every section but the first.
Without the Section column every section gets one, the first included, and a
rule is drawn even when `prinbox-section-separator' is nil, so each section
stays named.  Overlays only: the rows, their ids and the buffer's lines stay
as printed."
  (remove-overlays (point-min) (point-max) 'prinbox-separator t)
  (let ((style (or prinbox-section-separator (and (not prinbox-section-column) 'rule))))
    (when style
      (let ((width (max 20 (- (window-body-width (get-buffer-window (current-buffer))) 1)))
            (starts (if prinbox-section-column (cdr (prinbox--section-starts)) (prinbox--section-starts))))
        (dolist (start starts)
          (let* ((label (save-excursion
                          (goto-char start)
                          (aref (tabulated-list-get-entry) 0)))
                 (line (pcase style
                         ('blank "\n")
                         (_ (let* ((title (substring-no-properties label))
                                   (head (concat "── " (prinbox--with-icon (prinbox--section-kind title) title) " ")))
                              (concat (propertize head 'face (list (get-text-property 0 'face label)
                                                                   'prinbox-separator))
                                      (propertize (make-string (max 0 (- width (string-width head))) ?─)
                                                  'face 'prinbox-separator)
                                      "\n")))))
                 (overlay (make-overlay start start)))
            (overlay-put overlay 'prinbox-separator t)
            (overlay-put overlay 'before-string line)))))))

;;;###autoload
(defun prinbox ()
  "Show the pull requests waiting on you: the cache at once, then a refresh."
  (interactive)
  (pop-to-buffer (prinbox--buffer))
  (prinbox--inbox '("--cached")
                  (lambda (report)
                    (prinbox--render report)
                    (prinbox--inbox (list "--max-age" (number-to-string prinbox-max-age))
                                    #'prinbox--render))))

(defun prinbox-refresh ()
  "Fetch now and show the result when the buffer exists."
  (interactive)
  (prinbox--inbox nil (lambda (report) (when (get-buffer "*prinbox*") (prinbox--render report)))))

(defun prinbox--revert (&rest _)
  "The `revert-buffer-function': a refresh."
  (prinbox-refresh))

(defun prinbox--current-row ()
  "The row at point, or nil on a message line or a more line."
  (let ((id (tabulated-list-get-id)))
    (and id (not (string-prefix-p "message-" id)) (not (string-prefix-p "more-" id))
         (cdr (seq-find (lambda (item) (equal (alist-get 'id (cdr item)) id))
                        (prinbox--rows (plist-get prinbox--report :document)))))))

(defun prinbox--current-more ()
  "The section whose more line is at point, or nil."
  (when-let* ((id (tabulated-list-get-id))
              ((string-prefix-p "more-" id)))
    (seq-find (lambda (section) (equal (format "more-%s" (alist-get 'kind section)) id))
              (alist-get 'sections (plist-get prinbox--report :document)))))

(defun prinbox-open ()
  "Open the pull request at point in the browser.
On a more line, open the section's page on GitHub."
  (interactive)
  (if-let* ((row (prinbox--current-row)))
      (browse-url (prinbox--row-url row))
    (when-let* ((section (prinbox--current-more)))
      (browse-url (alist-get 'moreUrl section)))))

(defun prinbox--row-url (row)
  "The URL ROW opens.
That is GitHub's diff since your review when the diff moved,
else the pull request."
  (or (alist-get 'sinceReviewUrl (alist-get 'yourReview row))
      (alist-get 'url row)))

(defun prinbox--act (verb)
  "Run `prinbox VERB <id>' for the row at point, then re-read the cache."
  (when-let* ((row (prinbox--current-row)))
    (prinbox--process
     (list verb (alist-get 'id row))
     (lambda (code _out err)
       (list :ok (eql code 0)
             :message (string-trim (string-remove-prefix "prinbox: " (string-trim err)))))
     (lambda (result)
       (if (plist-get result :ok)
           (prinbox--inbox '("--cached") #'prinbox--render)
         (message "prinbox: %s" (plist-get result :message)))))))

(defun prinbox-snooze ()
  "Snooze the pull request at point until something happens on it."
  (interactive)
  (prinbox--act "snooze"))

(defun prinbox-unsnooze ()
  "Wake the snoozed pull request at point."
  (interactive)
  (prinbox--act "unsnooze"))

(defun prinbox-copy-link ()
  "Copy the URL at point to the kill ring: the one RET would open."
  (interactive)
  (when-let* ((url (if-let* ((row (prinbox--current-row)))
                       (prinbox--row-url row)
                     (alist-get 'moreUrl (prinbox--current-more)))))
    (kill-new url)
    (message "Copied %s" url)))

(defun prinbox-toggle-all ()
  "Show or hide the Reviewed section (`prinbox-all'), then fetch."
  (interactive)
  (setq prinbox-all (not prinbox-all))
  (message "prinbox: Reviewed section %s" (if prinbox-all "on" "off"))
  (prinbox-refresh))

(defun prinbox-next-section (&optional n)
  "Move to the first row of the next section.
With N, move N sections; a negative N moves backwards."
  (interactive "p")
  (let* ((n (or n 1))
         (here (line-beginning-position))
         (starts (prinbox--section-starts))
         (target (if (> n 0)
                     (nth (1- n) (seq-filter (lambda (p) (> p here)) starts))
                   (nth (1- (- n)) (reverse (seq-filter (lambda (p) (< p here)) starts))))))
    (if target
        (goto-char target)
      (message "prinbox: no %s section" (if (> n 0) "next" "previous")))))

(defun prinbox-previous-section (&optional n)
  "Move to the first row of this section.
When already there, move to the previous section; with N, N sections back."
  (interactive "p")
  (prinbox-next-section (- (or n 1))))

;;;; The mode line

(defun prinbox--mode-line ()
  "The mode-line segment."
  (if (string-empty-p prinbox-mode-line-string) "" (format " PR:%s" prinbox-mode-line-string)))

(defun prinbox--poll ()
  "A background refresh for the count.
It serves the cache up to `prinbox-poll-seconds' old."
  (prinbox--inbox (list "--max-age" (number-to-string (max prinbox-poll-seconds prinbox-max-age)))
                  (lambda (report) (when (get-buffer "*prinbox*") (prinbox--render report)))))

;;;###autoload
(define-minor-mode prinbox-mode-line-mode
  "Show the prinbox count in the mode line, refreshed every `prinbox-poll-seconds'."
  :global t
  (when prinbox--timer
    (cancel-timer prinbox--timer)
    (setq prinbox--timer nil))
  (unless (listp global-mode-string)
    (setq global-mode-string (list global-mode-string)))
  (cond
   (prinbox-mode-line-mode
    (add-to-list 'global-mode-string '(:eval (prinbox--mode-line)) t)
    (prinbox--poll)
    (when (> prinbox-poll-seconds 0)
      (setq prinbox--timer (run-with-timer prinbox-poll-seconds prinbox-poll-seconds #'prinbox--poll))))
   (t
    (setq global-mode-string (delete '(:eval (prinbox--mode-line)) global-mode-string)))))

(provide 'prinbox)
;;; prinbox.el ends here
