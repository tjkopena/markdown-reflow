;;; markdown-reflow.el --- Reflow Markdown section numbers, anchors, references -*- lexical-binding: t; -*-

;; Version: 1.0
;; Package-Requires: ((emacs "25.1"))
;; Keywords: convenience, outlines, wp

;;; Commentary:

;; Markdown sections are a convention for anchoring and referencing
;; nested numbered section headings in Markdown documents:
;;
;;     # My Software
;;
;;     ## 1. Introduction                                        ^intro
;;
;;     ## 2. Specification
;;     ### 2.1 Limitations                                       ^limits
;;
;;     As described in §intro:1 and motivated by §limits:2.1...
;;
;; `markdown-reflow' maintains that notation over a whole buffer:
;; dot-notation section numbers are renumbered in order without gaps,
;; references are updated with the number of the section they name, and
;; careted anchors are right-justified.
;;
;; Usage:
;;
;;   Load this file, or copy it into your `.emacs':
;;
;;     (require 'markdown-reflow)
;;
;;   Run `M-x markdown-reflow' in the buffer.  The function operates
;;   over the whole buffer, not the region, and leaves point where it
;;   was.  Narrowing is disregarded, section numbering being a property
;;   of the document as a whole.
;;
;;   To bind the function, apply `global-set-key' to a sequence
;;   reserved for users, e.g. `C-c' followed by a plain letter:
;;
;;     (global-set-key (kbd "C-c m") #'markdown-reflow)
;;
;;   Note that `C-c' followed by `<', `>', `{', `}', `:', `;', a digit,
;;   or a control character is reserved for major modes and will be
;;   shadowed in modes that claim it.
;;
;;   All changes made are logged to the *Messages* buffer and a summary
;;   reported to the echo area.
;;
;;   The edit is a single undo unit only if you have not touched the
;;   buffer in between; `C-_' may need repeating on a large document.
;;
;;   The preferred line width is defined by `fill-column' and tab stops
;;   by `tab-width'.
;;
;; The specification implemented here is markdown-reflow.md, whose
;; regexes are PCRE2 and normative as to behavior.  Emacs regexps offer
;; neither branch reset nor lookahead, so the patterns below decompose
;; them; each notes what it stands for.

;;; Code:

(require 'subr-x)


;;; Patterns

(defconst markdown-reflow--numbered-heading-re
  (concat "^\\(#\\{2,6\\}\\)[ \t]+"
          "\\(?:\\([0-9]+\\(?:\\.[0-9]+\\)+\\)\\.?"
          "\\|\\([0-9]+\\)\\.\\)"
          "\\([ \t]\\|$\\)")
  "Numbered section heading.
Stands for the specified

  ^(##+)[ \\t]+(?|([0-9]+(?:\\.[0-9]+)+)\\.?|([0-9]+)\\.)(?=[ \\t]|$)

with the hash run capped at six, the branch reset spelled out as
groups 2 and 3, and the lookahead as group 4, whose beginning is
where the title's leading whitespace starts.")

(defconst markdown-reflow--anchor-re
  (concat "^\\(#\\{2,6\\}\\)\\(?:.*[^ \t]\\)?"
          "\\([ \t]+\\)\\^\\([A-Za-z0-9_/#-]+\\)\\([ \t]*\\)$")
  "Anchor on a section heading line.
Stands for the specified

  ^(##+)(?=[ \\t])(?:.*[^ \\t])?([ \\t]+)\\^([A-Za-z0-9_/#-]+)([ \\t]*)$

The lookahead asserting whitespace after the hash run cannot be
written here and is checked by `markdown-reflow--anchor-match-p'.")

(defconst markdown-reflow--reference-re
  (concat "§\\([A-Za-z0-9_/#-]+\\)"
          "\\(?::\\(?:NOREF\\|DUPE\\|NONUM\\|[0-9]+\\(?:\\.[0-9]+\\)*\\)\\)?")
  "Reference to a section by its anchor.
Stands for the specified

  §([A-Za-z0-9_/#-]+)(:(?:NOREF|DUPE|NONUM|[0-9]+(?:\\.[0-9]+)*))?")

(defconst markdown-reflow--fence-open-re
  "^ \\{0,3\\}\\(?:\\(`\\{3,\\}\\)[^`]*\\|\\(~\\{3,\\}\\).*\\)$"
  "Opening fence, group 1 a backtick run and group 2 a tilde run.
Stands for the specified

  ^ {0,3}(?|(`{3,})([^`]*)|(~{3,})(.*))$")

(defconst markdown-reflow--fence-close-re
  "^ \\{0,3\\}\\(`\\{3,\\}\\|~\\{3,\\}\\)[ \t]*$"
  "Closing fence, bearing no info string.
Stands for the specified

  ^ {0,3}(`{3,}|~{3,})[ \\t]*$")

(defconst markdown-reflow--atx-line-re
  "^ \\{0,3\\}#\\{1,6\\}\\(?:[ \t]\\|$\\)"
  "GFM ATX heading line, which bounds an inline masking region.")

(defconst markdown-reflow--title-heading-re
  "^#\\(?:[ \t]\\|$\\)"
  "Single-hash heading, the document title.")

(defconst markdown-reflow--blank-re
  "\\`[ \t]*\\'"
  "A line holding nothing but whitespace.")

(defconst markdown-reflow--indent-tab-width 4
  "Tab stop width for the indentation that defines block structure.
Fixed by GFM at four columns, independent of `tab-width'.")


;;; Logging

(defvar markdown-reflow--changes nil
  "Changes logged by the reflow in progress, most recent first.")

(defvar markdown-reflow--problems nil
  "Errors and warnings logged by the reflow in progress, most recent first.")

(defun markdown-reflow--change (line format &rest args)
  "Log a change at LINE described by FORMAT and ARGS."
  (push (format "line %d: %s" line (apply #'format format args))
        markdown-reflow--changes))

(defun markdown-reflow--problem (line format &rest args)
  "Log an error or warning at LINE described by FORMAT and ARGS."
  (push (format "line %d: %s" line (apply #'format format args))
        markdown-reflow--problems))


;;; Lines and columns

(defun markdown-reflow--blank-p (line)
  "Return non-nil if LINE holds nothing but whitespace."
  (string-match-p markdown-reflow--blank-re line))

(defun markdown-reflow--indent-columns (line)
  "Return the indentation of LINE in columns.
Tabs are expanded to four-column tab stops, as GFM measures the
indentation that defines block structure."
  (let ((col 0)
        (i 0)
        (n (length line))
        (tw markdown-reflow--indent-tab-width)
        (done nil))
    (while (and (not done) (< i n))
      (let ((c (aref line i)))
        (cond ((eq c ?\s) (setq col (1+ col) i (1+ i)))
              ((eq c ?\t) (setq col (* tw (1+ (/ col tw))) i (1+ i)))
              (t (setq done t)))))
    col))

(defun markdown-reflow--display-column (string)
  "Return the display column just past STRING, counting from zero.
Tabs advance to the next `tab-width' stop; other characters count
their display width."
  (let ((col 0)
        (i 0)
        (n (length string))
        (tw (max 1 tab-width)))
    (while (< i n)
      (let ((c (aref string i)))
        (setq col (if (eq c ?\t)
                      (* tw (1+ (/ col tw)))
                    (+ col (char-width c)))))
      (setq i (1+ i)))
    col))

(defun markdown-reflow--buffer-lines ()
  "Return the lines of the accessible buffer portion as a vector."
  (vconcat (split-string (buffer-substring-no-properties (point-min) (point-max))
                         "\n")))


;;; Masking

;; Code blocks are found first and inline code only in what remains.
;; MARKS parallels the line vector: t masks a whole line, a bool-vector
;; masks the characters of one, nil masks nothing.

(defun markdown-reflow--masked-p (marks line col)
  "Return non-nil if column COL of LINE is masked in MARKS."
  (let ((m (aref marks line)))
    (cond ((eq m t) t)
          ((null m) nil)
          (t (and (< col (length m)) (aref m col))))))

(defun markdown-reflow--fence-open (line)
  "Return (CHAR . LENGTH) if LINE is an opening fence, else nil."
  (when (string-match markdown-reflow--fence-open-re line)
    (let ((run (or (match-string 1 line) (match-string 2 line))))
      (cons (aref run 0) (length run)))))

(defun markdown-reflow--fence-closes-p (line fence)
  "Return non-nil if LINE closes FENCE, a (CHAR . LENGTH) pair."
  (and (string-match markdown-reflow--fence-close-re line)
       (let ((run (match-string 1 line)))
         (and (eq (aref run 0) (car fence))
              (>= (length run) (cdr fence))))))

(defun markdown-reflow--scan-blocks (lines)
  "Return a vector marking each line of LINES that lies in a code block.
An unpaired fence is logged and masks the remainder of the document."
  (let* ((n (length lines))
         (code (make-vector n nil))
         (fence nil)
         (fence-line 0)
         (indented nil)
         ;; What the preceding line was, an indented code block being
         ;; able to begin only where it interrupts no paragraph.
         (prev 'start))
    (dotimes (i n)
      (let* ((line (aref lines i))
             (blank (markdown-reflow--blank-p line))
             (kind nil))
        (cond
         (fence
          (aset code i t)
          (setq kind 'code)
          (when (markdown-reflow--fence-closes-p line fence)
            (setq fence nil)))
         (t
          ;; An indented block ends at the first non-blank line
          ;; indented fewer than four columns, which is then read as
          ;; any other line.  Interior blank lines do not end it.
          (when (and indented
                     (not blank)
                     (< (markdown-reflow--indent-columns line) 4))
            (setq indented nil))
          (cond
           ((and indented blank)
            (setq kind 'blank))
           (indented
            (aset code i t)
            (setq kind 'code))
           ((markdown-reflow--fence-open line)
            (setq fence (markdown-reflow--fence-open line)
                  fence-line i)
            (aset code i t)
            (setq kind 'code))
           (blank
            (setq kind 'blank))
           ((and (>= (markdown-reflow--indent-columns line) 4)
                 (memq prev '(start blank heading code)))
            (setq indented t)
            (aset code i t)
            (setq kind 'code))
           ((string-match-p markdown-reflow--atx-line-re line)
            (setq kind 'heading))
           (t
            (setq kind 'para)))))
        (setq prev kind)))
    (when fence
      (markdown-reflow--problem (1+ fence-line)
                                "unpaired fence, masked to end of document"))
    code))

(defun markdown-reflow--backtick-runs (text)
  "Return the backtick strings of TEXT as a list of (START . LENGTH).
A run is maximal, and a backslash-escaped backtick is not part of
one."
  (let ((runs nil)
        (i 0)
        (n (length text)))
    (while (< i n)
      (let ((c (aref text i)))
        (cond ((eq c ?\\) (setq i (+ i 2)))
              ((eq c ?`)
               (let ((start i))
                 (while (and (< i n) (eq (aref text i) ?`))
                   (setq i (1+ i)))
                 (push (cons start (- i start)) runs)))
              (t (setq i (1+ i))))))
    (nreverse runs)))

(defun markdown-reflow--code-spans (text)
  "Return the code spans of TEXT as a list of (BEGIN . END) character ranges.
A backtick string opens a span closed by the next backtick string
of equal length; one that finds no closer is ordinary text."
  (let ((runs (markdown-reflow--backtick-runs text))
        (spans nil))
    (while runs
      (let* ((open (car runs))
             (scan (cdr runs))
             (close nil))
        (while (and scan (not close))
          (if (= (cdr (car scan)) (cdr open))
              (setq close (car scan))
            (setq scan (cdr scan))))
        (if close
            (progn
              (push (cons (car open) (+ (car close) (cdr close))) spans)
              (setq runs (cdr scan)))
          (setq runs (cdr runs)))))
    (nreverse spans)))

(defun markdown-reflow--mark-span (lines marks region begin end)
  "Mask characters BEGIN through END of REGION's text in MARKS.
REGION is a list of indices into LINES whose text is those lines
joined by newlines."
  (let ((offset 0))
    (dolist (i region)
      (let* ((len (length (aref lines i)))
             (from (max 0 (- begin offset)))
             (to (min len (- end offset))))
        (when (and (< from to) (< from len))
          (let ((m (aref marks i)))
            (unless (bool-vector-p m)
              (setq m (make-bool-vector len nil))
              (aset marks i m))
            (let ((k from))
              (while (< k to)
                (aset m k t)
                (setq k (1+ k))))))
        (setq offset (+ offset len 1))))))

(defun markdown-reflow--mask-region (lines marks region)
  "Mask the inline code spans of REGION, a list of indices into LINES, in MARKS."
  (when region
    (let ((text (mapconcat (lambda (i) (aref lines i)) region "\n")))
      (dolist (span (markdown-reflow--code-spans text))
        (markdown-reflow--mark-span lines marks region
                                    (car span) (cdr span))))))

(defun markdown-reflow--mask (lines)
  "Return the mask of LINES, a vector parallel to it.
Whole lines of code blocks are marked t and the characters of
inline code spans in bool-vectors."
  (let* ((n (length lines))
         (code (markdown-reflow--scan-blocks lines))
         (marks (make-vector n nil))
         (region nil))
    (dotimes (i n)
      (aset marks i (and (aref code i) t)))
    ;; Regions are the maximal runs of consecutive non-blank lines
    ;; outside code blocks, each heading line one of its own.
    (dotimes (i n)
      (let ((line (aref lines i)))
        (cond
         ((or (aref code i) (markdown-reflow--blank-p line))
          (markdown-reflow--mask-region lines marks (nreverse region))
          (setq region nil))
         ((string-match-p markdown-reflow--atx-line-re line)
          (markdown-reflow--mask-region lines marks (nreverse region))
          (setq region nil)
          (markdown-reflow--mask-region lines marks (list i)))
         (t
          (push i region)))))
    (markdown-reflow--mask-region lines marks (nreverse region))
    marks))


;;; Headings, anchors, and references

(defun markdown-reflow--anchor-match-p (line)
  "Return non-nil if LINE bears an anchor, leaving the match data set.
Supplies the lookahead the anchor pattern cannot express, that
whitespace follow the hash run."
  (and (string-match markdown-reflow--anchor-re line)
       (memq (aref line (match-end 1)) '(?\s ?\t))))

(defun markdown-reflow--number-string (counters depth)
  "Return the section number COUNTERS hold at DEPTH.
The number has exactly DEPTH components and a trailing dot if and
only if it is single-component."
  (let ((parts nil)
        (d depth))
    (while (> d 0)
      (push (number-to-string (aref counters d)) parts)
      (setq d (1- d)))
    (concat (string-join parts ".") (if (= depth 1) "." ""))))

(defun markdown-reflow--advance (counters depth current)
  "Advance COUNTERS to DEPTH, coming from CURRENT depth.
Skipped levels start at 1 and consume a slot; a shallower heading
increments its own counter and clears those beneath it."
  (if (> depth current)
      (let ((d (1+ current)))
        (while (<= d depth)
          (aset counters d 1)
          (setq d (1+ d))))
    (aset counters depth (1+ (aref counters depth)))
    (let ((d (1+ depth)))
      (while (<= d 5)
        (aset counters d 0)
        (setq d (1+ d))))))

(defun markdown-reflow--analyze (lines marks)
  "Study LINES under MARKS, returning the state the rewrite needs.
The value is a list of the vector of section numbers by line, the
vector of lines bearing a recognized anchor, and the table of
anchor identifiers, each entry a cons of its definition count and
the section number of the heading carrying it, nil if unnumbered."
  (let* ((n (length lines))
         (numbers (make-vector n nil))
         (anchored (make-vector n nil))
         (anchors (make-hash-table :test #'equal))
         (counters (make-vector 6 0))
         (current 0)
         (titled nil))
    (dotimes (i n)
      (unless (eq (aref marks i) t)
        (let ((line (aref lines i))
              (number nil))
          ;; Rule 1.2: only the first single-hash heading is accepted.
          (when (string-match-p markdown-reflow--title-heading-re line)
            (if titled
                (markdown-reflow--problem
                 (1+ i) "additional single-hash heading ignored: %s" line)
              (setq titled t)))
          (when (and (string-match markdown-reflow--numbered-heading-re line)
                     (not (markdown-reflow--masked-p
                           marks i (or (match-beginning 2)
                                       (match-beginning 3)))))
            (let ((depth (1- (length (match-string 1 line)))))
              (markdown-reflow--advance counters depth current)
              (setq current depth
                    number (markdown-reflow--number-string counters depth))
              (aset numbers i number)))
          (when (and (markdown-reflow--anchor-match-p line)
                     (not (markdown-reflow--masked-p marks i (match-end 2))))
            (let* ((id (match-string 3 line))
                   (entry (gethash id anchors)))
              (aset anchored i t)
              (if entry
                  (progn
                    (setcar entry (1+ (car entry)))
                    (markdown-reflow--problem
                     (1+ i) "anchor defined multiple times: ^%s" id))
                (puthash id (cons 1 number) anchors)))))))
    (list numbers anchored anchors)))

(defun markdown-reflow--resolve (id anchors line)
  "Return the appellation for a reference to ID in ANCHORS.
Any error is logged against LINE."
  (let ((entry (gethash id anchors)))
    (cond
     ((null entry)
      (markdown-reflow--problem (1+ line) "reference to undefined anchor: §%s" id)
      "NOREF")
     ((> (car entry) 1)
      ;; DUPE takes precedence over NONUM, but both are logged.
      (markdown-reflow--problem (1+ line) "reference to duplicated anchor: §%s" id)
      (unless (cdr entry)
        (markdown-reflow--problem
         (1+ line) "reference to unnumbered section: §%s" id))
      "DUPE")
     ((null (cdr entry))
      (markdown-reflow--problem (1+ line) "reference to unnumbered section: §%s" id)
      "NONUM")
     ;; A reference carries no trailing dot, being agnostic to the one
     ;; a single-component heading number bears.
     (t (string-remove-suffix "." (cdr entry))))))


;;; Rewriting

(defun markdown-reflow--update-references (line index marks anchors counts)
  "Return LINE with its unmasked references updated.
INDEX is the line's position, MARKS the mask, ANCHORS the table
of anchor identifiers, and COUNTS the tally each updated
reference is counted into."
  (let ((result "")
        (pos 0))
    (while (string-match markdown-reflow--reference-re line pos)
      (let* ((begin (match-beginning 0))
             (end (match-end 0))
             (id (match-string 1 line))
             (old (substring line begin end))
             (new (if (markdown-reflow--masked-p marks index begin)
                      old
                    (concat "§" id ":"
                            (markdown-reflow--resolve id anchors index)))))
        (unless (string= new old)
          (aset counts 1 (1+ (aref counts 1))))
        (setq result (concat result (substring line pos begin) new)
              pos end)))
    (concat result (substring line pos))))

(defun markdown-reflow--renumber (line number)
  "Return LINE bearing section NUMBER in place of the one it holds.
Whitespace about the number is normalized to a single space and
the title left as it stands."
  (if (not (string-match markdown-reflow--numbered-heading-re line))
      line
    (let* ((hashes (match-string 1 line))
           (rest (substring line (match-beginning 4)))
           (title (if (string-match "\\`[ \t]+" rest)
                      (substring rest (match-end 0))
                    rest)))
      (concat hashes " " number
              (if (string= title "") "" (concat " " title))))))

(defun markdown-reflow--justify (line width)
  "Return LINE with its anchor right-justified to WIDTH columns.
Whitespace before the anchor becomes the spaces that fill the
line and whitespace after it is deleted.  The padding is never
less than one space, so an anchor may overrun WIDTH."
  (if (not (markdown-reflow--anchor-match-p line))
      line
    (let* ((head (substring line 0 (match-beginning 2)))
           (id (match-string 3 line))
           (column (markdown-reflow--display-column head))
           (padding (max (- width column (length id) 1) 1)))
      (concat head (make-string padding ?\s) "^" id))))

(defun markdown-reflow--rewrite (lines marks numbers anchored anchors width counts)
  "Return the rewritten LINES as a vector, tallying the work into COUNTS.
MARKS is the mask, NUMBERS and ANCHORED the analysis of the
headings, ANCHORS the anchor table, and WIDTH the preferred line
width.  COUNTS is a vector of headings renumbered, references
updated, and anchors justified."
  (let* ((n (length lines))
         (result (make-vector n nil)))
    (dotimes (i n)
      (let ((line (aref lines i)))
        (aset result i line)
        (unless (eq (aref marks i) t)
          ;; Renumbering takes precedence over references and both over
          ;; justification.  References are applied to the line as it
          ;; stands, so that the mask still describes it, and touch no
          ;; part of it renumbering does.
          (let* ((referenced (markdown-reflow--update-references
                              line i marks anchors counts))
                 (numbered (if (aref numbers i)
                               (markdown-reflow--renumber referenced
                                                          (aref numbers i))
                             referenced))
                 (justified (if (aref anchored i)
                                (markdown-reflow--justify numbered width)
                              numbered)))
            (unless (string= numbered referenced)
              (aset counts 0 (1+ (aref counts 0))))
            (unless (string= justified numbered)
              (aset counts 2 (1+ (aref counts 2))))
            (aset result i justified)))))
    result))


;;; Application

(defun markdown-reflow--replace-line (begin end old new)
  "Replace the buffer text from BEGIN to END, holding OLD, with NEW.
Only the characters that differ are touched, so that point and
markers about them are left where they are."
  (let* ((old-length (length old))
         (new-length (length new))
         (common (min old-length new-length))
         (prefix 0)
         (suffix 0))
    (while (and (< prefix common)
                (eq (aref old prefix) (aref new prefix)))
      (setq prefix (1+ prefix)))
    (while (and (< suffix (- common prefix))
                (eq (aref old (- old-length suffix 1))
                    (aref new (- new-length suffix 1))))
      (setq suffix (1+ suffix)))
    (delete-region (+ begin prefix) (- end suffix))
    (save-excursion
      (goto-char (+ begin prefix))
      (insert (substring new prefix (- new-length suffix))))))

(defun markdown-reflow--apply (lines rewritten)
  "Replace each line of the buffer differing between LINES and REWRITTEN."
  (goto-char (point-min))
  (dotimes (i (length lines))
    (let ((old (aref lines i))
          (new (aref rewritten i)))
      (unless (string= old new)
        (markdown-reflow--replace-line (line-beginning-position)
                                       (line-end-position)
                                       old new)
        (markdown-reflow--change (1+ i) "%s -> %s" old new)))
    (forward-line 1)))

(defun markdown-reflow--report (counts)
  "Log the work COUNTS tallies and report a summary to the echo area."
  (let ((entries (nreverse markdown-reflow--problems))
        (changes (nreverse markdown-reflow--changes)))
    (let ((inhibit-message t))
      (dolist (entry entries)
        (message "markdown-reflow: %s" entry))
      (dolist (entry changes)
        (message "markdown-reflow: %s" entry)))
    (setq markdown-reflow--problems entries
          markdown-reflow--changes changes))
  (let ((headings (aref counts 0))
        (references (aref counts 1))
        (anchors (aref counts 2))
        (problems (length markdown-reflow--problems)))
    (if (and (zerop headings) (zerop references) (zerop anchors)
             (zerop problems))
        (message "markdown-reflow: no changes")
      (message
       "markdown-reflow: %d heading%s renumbered, %d reference%s updated, %d anchor%s justified%s"
       headings (if (= headings 1) "" "s")
       references (if (= references 1) "" "s")
       anchors (if (= anchors 1) "" "s")
       (if (zerop problems)
           ""
         (format ", %d problem%s logged"
                 problems (if (= problems 1) "" "s")))))))

;;;###autoload
(defun markdown-reflow ()
  "Reflow Markdown section numbering, anchors, and references.

Section numbers are renumbered so that the numbering at each
depth starts at 1, has no gaps, and is in order; references are
given the number of the section whose anchor they name; and
anchors are right-justified to `fill-column'.  Code blocks and
inline code are left alone.

The whole buffer is reflowed, whatever the region or narrowing,
and point is left where it was.  Changes are logged to the
*Messages* buffer and summarized in the echo area."
  (interactive)
  (barf-if-buffer-read-only)
  (let ((markdown-reflow--changes nil)
        (markdown-reflow--problems nil)
        (case-fold-search nil)
        (counts (make-vector 3 0)))
    (save-excursion
      (save-restriction
        (widen)
        (let* ((lines (markdown-reflow--buffer-lines))
               (marks (markdown-reflow--mask lines))
               (analysis (markdown-reflow--analyze lines marks))
               (rewritten (markdown-reflow--rewrite
                           lines marks
                           (nth 0 analysis) (nth 1 analysis) (nth 2 analysis)
                           fill-column counts)))
          (markdown-reflow--apply lines rewritten))))
    (markdown-reflow--report counts)))

(provide 'markdown-reflow)

;;; markdown-reflow.el ends here
