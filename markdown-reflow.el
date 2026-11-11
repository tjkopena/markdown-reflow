;;; markdown-reflow.el --- Reflow Markdown section numbers, anchors, references -*- lexical-binding: t; -*-

;; Copyright (C) 2026 tjkopena

;; Author: tjkopena <tjkopena@gmail.com>
;; Maintainer: tjkopena <tjkopena@gmail.com>
;; URL: https://github.com/tjkopena/markdown-reflow
;; Version: 1.2
;; Package-Requires: ((emacs "25.1"))
;; Keywords: convenience, outlines, wp

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

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
;; careted anchors are right-justified.  A reference may name an anchor
;; in another document by a path relative to this one, as in
;; §notes.md:intro:1.
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
;;   However many lines it touches, the reflow is one command and so
;;   one undo unit: a single `C-_' takes the whole of it back.
;;
;;   The preferred line width is `markdown-reflow-width', which defaults
;;   to `fill-column', and tab stops are `tab-width'.  The four-column
;;   tab stops by which GFM measures the indentation defining block
;;   structure are fixed by the specification and do not follow
;;   `tab-width'.
;;
;;   Paths of references to other documents are resolved against the
;;   directory of the file the buffer visits.  A buffer visiting no
;;   file cannot resolve them, and leaves such references alone.
;;
;; The specification implemented here is markdown-reflow.md, version
;; 1.2, whose regexes are PCRE2 and normative as to behavior.  Emacs
;; regexps offer neither branch reset nor lookahead, so the patterns
;; below decompose them; each notes what it stands for.

;;; Code:

(require 'subr-x)


;;; Customization

(defgroup markdown-reflow nil
  "Reflow Markdown section numbering, anchors, and references."
  :group 'text
  :prefix "markdown-reflow-")

(defcustom markdown-reflow-width nil
  "Preferred line width anchors are right-justified to.
Nil, the default, follows `fill-column', so that reflow honors
whatever width the buffer is already being filled to.  Set this
where anchors are to be justified to a width of their own, as when
a document is filled to 70 columns but ruled at 72."
  :type '(choice (const :tag "Follow `fill-column'" nil)
                 (integer :tag "Columns"))
  :group 'markdown-reflow)


;;; Patterns

(defconst markdown-reflow--numbered-heading-re
  (concat "^\\(#\\{2,6\\}\\)[ \t]+"
          "\\(?:\\([0-9]+\\(?:\\.[0-9]+\\)+\\)\\.?"
          "\\|\\([0-9]+\\)\\.\\)"
          "\\([ \t]\\|$\\)")
  "Numbered section heading.
Stands for the specified

  ^(#{2,6})[ \\t]+(?|([0-9]+(?:\\.[0-9]+)+)\\.?|([0-9]+)\\.)(?=[ \\t]|$)

with the branch reset spelled out as groups 2 and 3, and the
lookahead as group 4, whose beginning is where the title's leading
whitespace starts.")

(defconst markdown-reflow--anchor-re
  (concat "^\\(#\\{2,6\\}\\)\\(?:.*[^ \t]\\)?"
          "\\([ \t]+\\)\\^\\([A-Za-z0-9_/#-]+\\)\\([ \t]*\\)$")
  "Anchor on a section heading line.
Stands for the specified

  ^(#{2,6})(?=[ \\t])(?:.*[^ \\t])?([ \\t]+)\\^([A-Za-z0-9_/#-]+)([ \\t]*)$

The lookahead asserting whitespace after the hash run cannot be
written here and is checked by `markdown-reflow--anchor-match-p'.")

(defconst markdown-reflow--appellations-re
  "\\(?::[A-Za-z0-9_/#-]+\\(?:\\.[A-Za-z0-9_/#-]+\\)*\\)*"
  "The run of appellations closing a reference, matched shy.
However many appellations a reference carries, all are consumed
and one is emitted, so a stale number, an exception flag, and the
NONUM of earlier versions alike are taken by the class rather than
by an alternative naming each.  A colon opening no appellation ends
the match: one followed by whitespace or the end of the line, one
followed by a character that opens none, and one escaped with a
backslash, the backslash being no colon and so no separator.")

(defconst markdown-reflow--reference-re
  (concat "§\\([A-Za-z0-9_/#-]+\\)" markdown-reflow--appellations-re)
  "Reference to a section by its anchor, bearing no path.
Together with `markdown-reflow--path-reference-re' stands for the
specified

  §(?:((?!/)[A-Za-z0-9_/#.-]*\\.[A-Za-z0-9_/#.-]*+(?<!\\.)):)?
    ([A-Za-z0-9_/#-]++)((?::[A-Za-z0-9_/#-]+(?:\\.[A-Za-z0-9_/#-]+)*)*)
    (?!\\.[A-Za-z0-9_/#-])

with the path alternative split out, the identifier here group 1,
and the run of appellations matched shy where the specification
captures it as group 3, the rewrite working from the whole match.
The closing lookahead is checked by
`markdown-reflow--dot-opens-appellation-p'.  The identifier is
possessive in the specification, and an Emacs regexp needs no such
care: the lookahead is checked after matching, and a rejected match
is never retried shorter.")

(defconst markdown-reflow--path-reference-re
  (concat "§\\([A-Za-z0-9_/#.-]+\\):\\([A-Za-z0-9_/#-]+\\)"
          markdown-reflow--appellations-re)
  "Reference to a section by its anchor in another document.
Group 1 is the path and group 2 the anchor identifier.  The path
class holds no colon, so group 1 is always the whole run from the
section mark to the first colon.  That it hold a dot, open with no
slash, and close with no dot, which the specified lookarounds
assert, is checked by `markdown-reflow--path-p'.  Where any of
those or the closing lookahead fails, the match is retried as
`markdown-reflow--reference-re', as the specified optional group
would be.")

(defconst markdown-reflow--identifier-char-re
  "\\`[A-Za-z0-9_/#-]\\'"
  "One character of an anchor identifier or an appellation.
The specified [A-Za-z0-9_/#-], anchored so that it matches a
single character rather than searching for one.")

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

(defvar markdown-reflow--origin nil
  "File name of the document being reflowed, nil where it has none.
Paths of references are resolved against its directory.")

(defvar markdown-reflow--targets nil
  "Anchor tables of the documents the reflow in progress has read.
A hash table from true file name to anchor table, or to nil for a
document that cannot be read, so that each is read once and every
reference to it resolves against the same text.")

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
           ((setq fence (markdown-reflow--fence-open line))
            (setq fence-line i)
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
          ;; The mask is consulted for the number and the caret alike
          ;; though neither can in fact fall within a code span today:
          ;; whole lines of code blocks are already skipped above, and
          ;; a heading line is a masking region of its own, so a span
          ;; masking the number would need a backtick ahead of it,
          ;; where the heading pattern admits only whitespace, and one
          ;; masking the caret would have to close after the anchor,
          ;; where the anchor pattern admits only whitespace and the
          ;; end of the line.  The checks stand against a widening of
          ;; either pattern, section 3 of the specification holding
          ;; without qualification that anchors within inline code are
          ;; ignored.
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

(defun markdown-reflow--resolve (id anchors line &optional path)
  "Return the appellation for a reference to ID in ANCHORS.
The value is nil where the section bears no number, there being
nothing to expand the reference with; the caller then emits the
bare reference.  Only an anchor that does not exist is logged,
against LINE, there being no heading to log it against.  A
duplicated anchor is a property of the heading lines and was
logged against each redefinition by `markdown-reflow--analyze',
whatever the references it spoils, or is the concern of the
target at PATH, which logs it when it is itself reflowed."
  (let ((entry (gethash id anchors)))
    (cond
     ((null entry)
      (markdown-reflow--problem (1+ line) "reference to undefined anchor: §%s%s"
                                (if path (concat path ":") "") id)
      "NOREF")
     ;; A duplicated anchor is flagged whether or not it is numbered.
     ((> (car entry) 1)
      "DUPE")
     ;; An anchor on an unnumbered section is no error.  The reference
     ;; is left bare, shedding any appellation it arrived with.
     ((null (cdr entry))
      nil)
     ;; A reference carries no trailing dot, being agnostic to the one
     ;; a single-component heading number bears.
     (t (string-remove-suffix "." (cdr entry))))))


;;; Targets

(defun markdown-reflow--path-p (path)
  "Return non-nil if PATH, a run of path characters, is a path.
A path holds a dot, which tells it from an anchor identifier, opens
with no slash, being always relative, and closes with no dot, so
that a reference closing a sentence ahead of a colon reads as it
did before paths were recognized."
  (and (string-match-p "\\." path)
       (not (string-prefix-p "/" path))
       (not (string-suffix-p "." path))))

(defun markdown-reflow--read-target (file)
  "Return the anchor table of FILE, nil if it cannot be read.
FILE is studied as reflow would number it, so the numbers written in
it are not consulted.  Defects within it are its own, logged when it
is itself reflowed, so whatever its analysis logs is discarded."
  (when (and (file-regular-p file) (file-readable-p file))
    (condition-case nil
        (with-temp-buffer
          (let ((coding-system-for-read 'utf-8))
            (insert-file-contents file))
          (let* ((markdown-reflow--problems nil)
                 (case-fold-search nil)
                 (lines (markdown-reflow--buffer-lines)))
            (nth 2 (markdown-reflow--analyze
                    lines (markdown-reflow--mask lines)))))
      (file-error nil))))

(defun markdown-reflow--target-anchors (path)
  "Return the anchor table of the document at PATH, nil if unreadable.
PATH is resolved against the directory of `markdown-reflow--origin'
and each document read once per reflow.  The document being reflowed
is entered beforehand, so a path naming it yields its anchors as this
reflow numbers them, not as last saved."
  (let* ((file (file-truename
                (expand-file-name path (file-name-directory
                                        markdown-reflow--origin))))
         (table (gethash file markdown-reflow--targets 'unread)))
    (if (eq table 'unread)
        (puthash file (markdown-reflow--read-target file)
                 markdown-reflow--targets)
      table)))


;;; Rewriting

(defun markdown-reflow--dot-opens-appellation-p (line end)
  "Return non-nil if a dot at END in LINE would open an appellation.
Supplies the negative lookahead closing the reference pattern.  A
match trailed by a dot and an identifier character is no reference:
an appellation emitted ahead of that dot would join the text after
it into one dot-separated run, which the next reflow would consume
whole, and rule 0 forbids a transformation that does not stand.

The lookahead can bite only where the run of appellations is
empty, a non-empty run having already taken any dot that could
follow it."
  (and (< (1+ end) (length line))
       (eq (aref line end) ?.)
       (string-match-p markdown-reflow--identifier-char-re
                       (string (aref line (1+ end))))))

(defun markdown-reflow--next-reference (line pos)
  "Return the next match of a reference in LINE at or after POS, or nil.
The value is a list (BEGIN END PATH ID): the extent of the match,
its path, nil where it bears none, and its anchor identifier, nil
where the match is no reference and is to be left whole.  A path
form failing its constraints or the closing lookahead is retried
without the path, as the specified optional group would be, and a
section mark opening no reference at all is matched alone."
  (let ((begin (string-match "§" line pos)))
    (when begin
      (or (and (eql (string-match markdown-reflow--path-reference-re line begin)
                    begin)
               (markdown-reflow--path-p (match-string 1 line))
               (not (markdown-reflow--dot-opens-appellation-p line (match-end 0)))
               (list begin (match-end 0) (match-string 1 line) (match-string 2 line)))
          (and (eql (string-match markdown-reflow--reference-re line begin) begin)
               (list begin (match-end 0) nil
                     (unless (markdown-reflow--dot-opens-appellation-p
                              line (match-end 0))
                       (match-string 1 line))))
          (list begin (1+ begin) nil nil)))))

(defun markdown-reflow--reference (path id anchors line old)
  "Return the text of the reference to ID, bearing PATH, at LINE.
ANCHORS is the table of the document being reflowed, consulted
where PATH is nil.  Where PATH names a document that cannot be read,
or the document being reflowed has no location to resolve it
against, the error is logged and OLD, the reference as it stands,
returned whole, leaving its last resolution in place."
  (let ((table (cond ((null path) anchors)
                     (markdown-reflow--origin
                      (markdown-reflow--target-anchors path)))))
    (cond
     (table
      (let ((appellation (markdown-reflow--resolve id table line path)))
        (concat "§" (if path (concat path ":") "") id
                (if appellation (concat ":" appellation) ""))))
     (markdown-reflow--origin
      (markdown-reflow--problem (1+ line) "reference to unreadable document: §%s:%s"
                                path id)
      old)
     (t
      (markdown-reflow--problem
       (1+ line) "reference to another document from one with no file: §%s:%s"
       path id)
      old))))

(defun markdown-reflow--update-references (line index marks anchors counts)
  "Return LINE with its unmasked references updated.
INDEX is the line's position, MARKS the mask, ANCHORS the table
of anchor identifiers, and COUNTS the tally each updated
reference is counted into.  A reference to an unnumbered section
has no appellation to take and is emitted bare.  A masked match
and one the closing lookahead rejects are alike left whole, and
neither is resolved, so neither draws a log."
  (let ((result "")
        (pos 0)
        (match nil))
    (while (setq match (markdown-reflow--next-reference line pos))
      (let* ((begin (nth 0 match))
             (end (nth 1 match))
             (id (nth 3 match))
             (old (substring line begin end))
             (new (if (or (null id)
                          (markdown-reflow--masked-p marks index begin))
                      old
                    (markdown-reflow--reference (nth 2 match) id anchors
                                                index old))))
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
  (let* ((entries (nreverse markdown-reflow--problems))
         (changes (nreverse markdown-reflow--changes))
         (headings (aref counts 0))
         (references (aref counts 1))
         (anchors (aref counts 2))
         (problems (length entries)))
    (let ((inhibit-message t))
      (dolist (entry entries)
        (message "markdown-reflow: %s" entry))
      (dolist (entry changes)
        (message "markdown-reflow: %s" entry)))
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

(defun markdown-reflow--width ()
  "Return the preferred line width anchors are justified to.
`markdown-reflow-width' where it is set, otherwise `fill-column',
which may itself be nil where filling is disabled; the Emacs
default of 70 stands in for that."
  (or markdown-reflow-width fill-column 70))

;;;###autoload
(defun markdown-reflow ()
  "Reflow Markdown section numbering, anchors, and references.

Section numbers are renumbered so that the numbering at each
depth starts at 1, has no gaps, and is in order; references are
given the number of the section whose anchor they name, in this
document or in another named by a path relative to this one's file;
and anchors are right-justified to `markdown-reflow-width', which
defaults to `fill-column'.  Code blocks and inline code are left
alone.

The whole buffer is reflowed, whatever the region or narrowing,
and point is left where it was.  Changes are logged to the
*Messages* buffer and summarized in the echo area."
  (interactive)
  (barf-if-buffer-read-only)
  (let ((markdown-reflow--changes nil)
        (markdown-reflow--problems nil)
        (markdown-reflow--origin buffer-file-name)
        (markdown-reflow--targets (make-hash-table :test #'equal))
        (case-fold-search nil)
        (counts (make-vector 3 0)))
    (save-excursion
      (save-restriction
        (widen)
        (let* ((lines (markdown-reflow--buffer-lines))
               (marks (markdown-reflow--mask lines))
               (analysis (markdown-reflow--analyze lines marks)))
          ;; A path naming this document resolves against it as reflowed
          ;; here, not as last saved.
          (when markdown-reflow--origin
            (puthash (file-truename markdown-reflow--origin) (nth 2 analysis)
                     markdown-reflow--targets))
          (markdown-reflow--apply
           lines
           (markdown-reflow--rewrite
            lines marks
            (nth 0 analysis) (nth 1 analysis) (nth 2 analysis)
            (markdown-reflow--width) counts)))))
    (markdown-reflow--report counts)))

(provide 'markdown-reflow)

;;; markdown-reflow.el ends here
