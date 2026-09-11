;;; markdown-reflow-test.el --- Tests for markdown-reflow -*- lexical-binding: t; coding: utf-8; -*-

;;; Commentary:

;; Test cases for markdown-reflow.el, covering the transformation
;; rules, code block and inline code masking, and both normative
;; conformance fixtures of markdown-reflow.md.
;;
;; Run in batch mode:
;;
;;   emacs -Q --batch -l markdown-reflow-test.el

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'subr-x)

(add-to-list 'load-path
             (file-name-directory (or load-file-name buffer-file-name)))
(require 'markdown-reflow)


;;; Helpers

(defun mrt--reflow (input &optional width tab)
  "Return INPUT reflowed under `fill-column' WIDTH and `tab-width' TAB.
`markdown-reflow-width' is held at nil so that the width under
test is the one given here."
  (with-temp-buffer
    (insert input)
    (setq fill-column (or width 72)
          tab-width (or tab 8))
    (let ((markdown-reflow-width nil)
          (inhibit-message t))
      (markdown-reflow))
    (buffer-string)))

(defmacro mrt--with-log (&rest body)
  "Evaluate BODY, returning the lines it logs through `message'.
`message' is displaced for the extent of BODY so that what a
single reflow logs is isolated, the shared *Messages* buffer
carrying whatever earlier tests have already put in it."
  (declare (indent 0) (debug t))
  `(let ((mrt--log nil))
     (cl-letf (((symbol-function 'message)
                (lambda (format &rest args)
                  (when format
                    (push (apply #'format format args) mrt--log))
                  nil)))
       ,@body)
     (string-join (nreverse mrt--log) "\n")))

(defun mrt--log-of (input &optional width)
  "Return what reflowing INPUT under `fill-column' WIDTH logs."
  (mrt--with-log
    (with-temp-buffer
      (insert input)
      (setq fill-column (or width 72)
            tab-width 8)
      (let ((markdown-reflow-width nil))
        (markdown-reflow)))))

(defun mrt--lines (&rest lines)
  "Return LINES joined by newlines."
  (string-join lines "\n"))

(defun mrt--justified (head id &optional width)
  "Return HEAD with anchor ID right-justified to WIDTH columns."
  (let* ((width (or width 72))
         (padding (max (- width (length head) (length id) 1) 1)))
    (concat head (make-string padding ?\s) "^" id)))


;;; Normative fixtures of markdown-reflow.md

(defconst mrt--worked-input
  (string-join
   (list
    "# My Document"
    "## Copyright ^legal"
    "## 2. Notes"
    "### 2.1 From A Pagan Nation"
    "As discussed in §problematic, blah blah blah..."
    "Also see §legal, §bogus, and §dup."
    "Colons: §legal:1:2, §problematic:9:9."
    "Then: §legal: one, §problematic: two."
    "Escaped: §legal\\:NO and §problematic\\:NO."
    "Dotted: §legal.b and §problematic.b."
    "## 4.9 Gibberish"
    "### 4.1 Anchored and full                                ^notes/gib1-a#b"
    "### 4.12. Two digits going to one"
    "# Not a new document"
    "###  4.1    Unjustified anchor ^x"
    "### 4.1 Much too much padding                                               ^problematic"
    "### 4.2 An overlong title that leaves no room at all for its anchor ^tight"
    "##### 9.9.9.9 Skipped levels ^dup"
    "### 9. Duplicated anchor ^dup"
    "### 9.9 See §problematic for terms ^terms"
    "Masked and so untouched: `§bogus` and"
    "~~~text"
    "## 7. Not a heading ^notanchor"
    "See §problematic in here too."
    "~~~")
   "\n")
  "Input of the worked example, section 6 of markdown-reflow.md.")

(defconst mrt--worked-output
  (string-join
   (list
    "# My Document"
    "## Copyright                                                      ^legal"
    "## 1. Notes"
    "### 1.1 From A Pagan Nation"
    "As discussed in §problematic:2.4, blah blah blah..."
    "Also see §legal, §bogus:NOREF, and §dup:DUPE."
    "Colons: §legal, §problematic:2.4."
    "Then: §legal: one, §problematic:2.4: two."
    "Escaped: §legal\\:NO and §problematic:2.4\\:NO."
    "Dotted: §legal.b and §problematic.b."
    "## 2. Gibberish"
    "### 2.1 Anchored and full                                ^notes/gib1-a#b"
    "### 2.2 Two digits going to one"
    "# Not a new document"
    "### 2.3 Unjustified anchor                                            ^x"
    "### 2.4 Much too much padding                               ^problematic"
    "### 2.5 An overlong title that leaves no room at all for its anchor ^tight"
    "##### 2.5.1.1 Skipped levels                                        ^dup"
    "### 2.6 Duplicated anchor                                           ^dup"
    "### 2.7 See §problematic:2.4 for terms                            ^terms"
    "Masked and so untouched: `§bogus` and"
    "~~~text"
    "## 7. Not a heading ^notanchor"
    "See §problematic in here too."
    "~~~")
   "\n")
  "Output of the worked example, section 6 of markdown-reflow.md.")

(defconst mrt--code-input
  (string-join
   (list
    "# Fixture"
    ""
    "## 2. Masking"
    "### 2.3 Anchored ^mask"
    ""
    "Text before an indented fence:"
    "    ```"
    "    See §mask here."
    ""
    "    Indented code holding §mask and"
    ""
    "    a second chunk, §mask masked too."
    ""
    "Live again: §mask."
    ""
    "```"
    "fenced content, §mask masked"
    "``` js"
    "still masked, §mask"
    "```"
    ""
    "``` a`b"
    "Not a fence, so §mask resolves."
    ""
    "An unmatched backtick ` ends this paragraph."
    ""
    "Still live: §mask."
    ""
    "## 3. Odd ` in a title"
    ""
    "Live here: §mask, and then a backtick ` closes nothing.")
   "\n")
  "Input of the code block fixture, section 7 of markdown-reflow.md.")

(defconst mrt--code-output
  (string-join
   (list
    "# Fixture"
    ""
    "## 1. Masking"
    "### 1.1 Anchored                                                   ^mask"
    ""
    "Text before an indented fence:"
    "    ```"
    "    See §mask:1.1 here."
    ""
    "    Indented code holding §mask and"
    ""
    "    a second chunk, §mask masked too."
    ""
    "Live again: §mask:1.1."
    ""
    "```"
    "fenced content, §mask masked"
    "``` js"
    "still masked, §mask"
    "```"
    ""
    "``` a`b"
    "Not a fence, so §mask:1.1 resolves."
    ""
    "An unmatched backtick ` ends this paragraph."
    ""
    "Still live: §mask:1.1."
    ""
    "## 2. Odd ` in a title"
    ""
    "Live here: §mask:1.1, and then a backtick ` closes nothing.")
   "\n")
  "Output of the code block fixture, section 7 of markdown-reflow.md.")

(ert-deftest mrt-worked-example ()
  "The conformance fixture of section 6 of markdown-reflow.md."
  (should (equal (mrt--reflow mrt--worked-input) mrt--worked-output)))

(ert-deftest mrt-code-block-fixture ()
  "The conformance fixture of section 7 of markdown-reflow.md."
  (should (equal (mrt--reflow mrt--code-input) mrt--code-output)))

(ert-deftest mrt-introductory-example ()
  "The example opening README.md."
  (should (equal
           (mrt--reflow
            (mrt--lines "# My Document" "" "Some text" "" "## Copyright" ""
                        "More text" "" "## 2. Notes"
                        "### 2.2 From A Pagan Nation ^pagans" ""
                        "Great content heah" "" "## 4. Gibberish"
                        "Four score and seven years ago (§pagans)."))
           (mrt--lines "# My Document" "" "Some text" "" "## Copyright" ""
                       "More text" "" "## 1. Notes"
                       (mrt--justified "### 1.1 From A Pagan Nation" "pagans") ""
                       "Great content heah" "" "## 2. Gibberish"
                       "Four score and seven years ago (§pagans:1.1)."))))


;;; Rule 0: idempotency

(ert-deftest mrt-idempotent-worked-example ()
  (should (equal (mrt--reflow mrt--worked-output) mrt--worked-output)))

(ert-deftest mrt-idempotent-code-block-fixture ()
  (should (equal (mrt--reflow mrt--code-output) mrt--code-output)))

(ert-deftest mrt-idempotent-twice ()
  (let ((once (mrt--reflow mrt--worked-input)))
    (should (equal (mrt--reflow once) once))))


;;; Rule 1: section numbering

(ert-deftest mrt-first-heading-deep ()
  "Rule 1.1: a document opening at depth 3 is numbered 1.1.1."
  (should (equal (mrt--reflow "#### 9. Deep") "#### 1.1.1 Deep")))

(ert-deftest mrt-skipped-levels-consume-a-slot ()
  "Rule 1.1: skipped levels start at 1 and consume a slot."
  (should (equal (mrt--reflow (mrt--lines "## 1. Top" "##### 9.9.9.9 Deep"))
                 (mrt--lines "## 1. Top" "##### 1.1.1.1 Deep"))))

(ert-deftest mrt-resuming-a-shallower-counter ()
  "Rule 1.1: after 1.1.1.1 a depth 2 heading is 1.2, not 1.1."
  (should (equal (mrt--reflow
                  (mrt--lines "## 1. Top" "##### 1.1.1.1 Deep" "### 9. Back"))
                 (mrt--lines "## 1. Top" "##### 1.1.1.1 Deep" "### 1.2 Back"))))

(ert-deftest mrt-additional-title-headings ()
  "Rule 1.2: later single-hash headings are ignored."
  (should (equal (mrt--reflow (mrt--lines "# Title" "## 1. Introduction"
                                          "# Chapter 1" "## 4. Content"))
                 (mrt--lines "# Title" "## 1. Introduction"
                             "# Chapter 1" "## 2. Content"))))

(ert-deftest mrt-inert-headings ()
  "Rule 1.3: unnumbered headings neither take a number nor a slot."
  (should (equal (mrt--reflow (mrt--lines "## Copyright" "## 5. Notes"
                                          "## 2024 Retrospective" "## 9. Gibberish"))
                 (mrt--lines "## Copyright" "## 1. Notes"
                             "## 2024 Retrospective" "## 2. Gibberish"))))

(ert-deftest mrt-component-count-sheds-dot ()
  "Rule 1.4: a depth 2 number keeps two components and sheds its dot."
  (should (equal (mrt--reflow
                  (mrt--lines "## 1. First" "## 2. Second" "### 2.1. Good Section"))
                 (mrt--lines "## 1. First" "## 2. Second" "### 2.1 Good Section"))))

(ert-deftest mrt-component-count-gains-dot ()
  "Rule 1.4: a depth 1 number is reduced to one component and gains a dot."
  (should (equal (mrt--reflow (mrt--lines "## 1. First" "## 2.1 Ok Section"))
                 (mrt--lines "## 1. First" "## 2. Ok Section"))))

(ert-deftest mrt-whitespace-normalized ()
  "Rule 1.5: whitespace about the number becomes a single space."
  (should (equal (mrt--reflow (mrt--lines "## 1. First" "##  2.    Ok Section"))
                 (mrt--lines "## 1. First" "## 2. Ok Section")))
  (should (equal (mrt--reflow "##\t9.\t\tTabbed") "## 1. Tabbed")))

(ert-deftest mrt-untitled-heading ()
  "A heading with no title keeps none, and no trailing whitespace."
  (should (equal (mrt--reflow "## 5.") "## 1."))
  (should (equal (mrt--reflow "##   9.   ") "## 1.")))

(ert-deftest mrt-counters-by-tier ()
  "Rule 1.6: a deeper depth starts its counter at 1."
  (should (equal (mrt--reflow
                  (mrt--lines "## 2. First Tier" "### 2.3 First Point"
                              "### 2.6 Second Point" "## 1. Back to First Tier"
                              "### 1.8 First Point" "### 1.1 Second Point"))
                 (mrt--lines "## 1. First Tier" "### 1.1 First Point"
                             "### 1.2 Second Point" "## 2. Back to First Tier"
                             "### 2.1 First Point" "### 2.2 Second Point"))))

(ert-deftest mrt-six-hashes-is-depth-five ()
  (should (equal (mrt--reflow "###### 9. Six") "###### 1.1.1.1.1 Six")))

(ert-deftest mrt-seven-hashes-is-no-heading ()
  "A run of seven hash marks opens no heading, so it bears no anchor."
  (should (equal (mrt--reflow (mrt--lines "####### 9. Not a heading ^x" "See §x."))
                 (mrt--lines "####### 9. Not a heading ^x" "See §x:NOREF."))))

(ert-deftest mrt-atx-closing-sequence ()
  "A heading closing with hash marks is numbered but carries no anchor."
  (should (equal (mrt--reflow "## 9. Foo ##") "## 1. Foo ##"))
  (should (equal (mrt--reflow "## Foo ^x ##") "## Foo ^x ##")))

(ert-deftest mrt-indented-heading-is-inert ()
  (should (equal (mrt--reflow "   ## 9. Indented") "   ## 9. Indented")))


;;; Rule 2: anchor justification

(ert-deftest mrt-anchor-justified ()
  (let ((out (mrt--reflow "## 4. Conclusion ^conclusion")))
    (should (equal out (concat "## 1. Conclusion" (make-string 45 ?\s)
                               "^conclusion")))
    (should (= 72 (length out)))))

(ert-deftest mrt-anchor-trailing-whitespace-deleted ()
  "Rule 2.1: whitespace after the anchor is deleted."
  (let ((out (mrt--reflow "## 9. A ^x   \t")))
    (should (equal out (concat "## 1. A" (make-string 63 ?\s) "^x")))
    (should (= 72 (length out)))))

(ert-deftest mrt-anchor-padding-replaces-tabs ()
  "Rule 2.2: whitespace before the anchor becomes filling spaces."
  (should (equal (mrt--reflow "## 9. A\t^x")
                 (concat "## 1. A" (make-string 63 ?\s) "^x"))))

(ert-deftest mrt-anchor-padding-has-a-floor ()
  "Rule 2.2: padding is never less than a single space."
  (let ((head (concat "## 1. " (make-string 70 ?x))))
    (should (equal (mrt--reflow (concat head " ^y"))
                   (concat head " ^y")))))

(ert-deftest mrt-anchor-columns-count-wide-characters ()
  "Rule 2.3: widths are display columns, so a double-width character
takes two of them though it is one character."
  (let ((out (mrt--reflow "## 9. 中文 ^a" 40)))
    (should (equal out (concat "## 1. 中文" (make-string 28 ?\s) "^a")))
    (should (= 40 (string-width out)))
    (should (= 38 (length out)))))

(ert-deftest mrt-anchor-width-follows-the-defcustom ()
  "`markdown-reflow-width' overrides `fill-column' where it is set."
  (with-temp-buffer
    (insert "## 9. A ^a")
    (setq fill-column 70)
    (let ((markdown-reflow-width 40)
          (inhibit-message t))
      (markdown-reflow))
    (should (equal (buffer-string)
                   (concat "## 1. A" (make-string 31 ?\s) "^a"))))
  ;; Nil, the default, follows `fill-column'.
  (should (equal (mrt--reflow "## 9. A ^a" 40)
                 (concat "## 1. A" (make-string 31 ?\s) "^a"))))

(ert-deftest mrt-anchor-columns-follow-tab-width ()
  "Rule 2.3: widths are display columns, tabs by `tab-width'."
  ;; "## 1. AB" is eight columns, so the tab reaches column 16 or 12
  ;; and "C" column 17 or 13.
  (should (equal (mrt--reflow "## 9. AB\tC ^x" 72 8)
                 (concat "## 1. AB\tC" (make-string 53 ?\s) "^x")))
  (should (equal (mrt--reflow "## 9. AB\tC ^x" 72 4)
                 (concat "## 1. AB\tC" (make-string 57 ?\s) "^x"))))

(ert-deftest mrt-anchor-width-follows-fill-column ()
  (let ((out (mrt--reflow "## 9. A ^x" 40)))
    (should (equal out (concat "## 1. A" (make-string 31 ?\s) "^x")))
    (should (= 40 (length out)))))

(ert-deftest mrt-last-caret-is-the-anchor ()
  (should (equal (mrt--reflow "## 9. A ^b ^x" 40)
                 (concat "## 1. A ^b" (make-string 28 ?\s) "^x"))))

(ert-deftest mrt-anchor-on-unnumbered-heading ()
  (let ((out (mrt--reflow "## Copyright ^legal")))
    (should (equal out (concat "## Copyright" (make-string 54 ?\s) "^legal")))
    (should (= 72 (length out)))))


;;; Rule 3: references

(ert-deftest mrt-reference-numbered ()
  "Rule 3: a reference takes the number of its section, with or without one."
  (should (equal (mrt--reflow (mrt--lines "## 9. A ^a" "See §a, §a:0.0.0, §a:NOREF.")
                              40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "See §a:1, §a:1, §a:1."))))

(ert-deftest mrt-reference-undefined ()
  "Rule 3.1: a reference to no anchor is NOREF."
  (should (equal (mrt--reflow "See §bogus.") "See §bogus:NOREF.")))

(ert-deftest mrt-reference-duplicated ()
  "Rule 3.2: a reference to a duplicated anchor is DUPE."
  (should (equal (mrt--reflow (mrt--lines "## 9. A ^d" "## 9. B ^d" "See §d.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^d")
                             (concat "## 2. B" (make-string 31 ?\s) "^d")
                             "See §d:DUPE."))))

(ert-deftest mrt-reference-unnumbered ()
  "Rule 3.3: a reference to an unnumbered section is left bare."
  (should (equal (mrt--reflow (mrt--lines "## A ^u" "See §u.") 40)
                 (mrt--lines (concat "## A" (make-string 34 ?\s) "^u")
                             "See §u."))))

(ert-deftest mrt-reference-unnumbered-sheds-its-appellation ()
  "Rule 3.3: every colon and appellation the reference arrived with goes.
A stale number and the NONUM of earlier versions alike are taken by
the appellation class rather than by an alternative naming each."
  (should (equal (mrt--reflow
                  (mrt--lines "## A ^u" "See §u:NONUM, §u:1.2, §u:9, and §u.")
                  40)
                 (mrt--lines (concat "## A" (make-string 34 ?\s) "^u")
                             "See §u, §u, §u, and §u."))))

(ert-deftest mrt-reference-multiple-appellations ()
  "Rule 3.4: however many appellations a reference carries, one is emitted."
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "See §a:1:2:3, §a:NOREF:9, §a:x.y:z.")
                  40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "See §a:1, §a:1, §a:1.")))
  (should (equal (mrt--reflow (mrt--lines "## A ^u" "See §u:1:2 and §u:9:9:9.") 40)
                 (mrt--lines (concat "## A" (make-string 34 ?\s) "^u")
                             "See §u and §u."))))

(ert-deftest mrt-reference-colon-before-whitespace ()
  "Rule 3.4: a colon followed by whitespace or end of line opens none.
Neither the colon nor the text after it is touched, and no escape is
added to either."
  (should (equal (mrt--reflow (mrt--lines "## 9. A ^a" "See §a: Text.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "See §a:1: Text.")))
  (should (equal (mrt--reflow (mrt--lines "## A ^u" "See §u: Text.") 40)
                 (mrt--lines (concat "## A" (make-string 34 ?\s) "^u")
                             "See §u: Text.")))
  (should (equal (mrt--reflow (mrt--lines "## 9. A ^a" "See §a:") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "See §a:1:"))))

(ert-deftest mrt-reference-escaped-colon ()
  "Rule 3.4: an escaped colon opens no appellation and is not removed.
The number is emitted ahead of the escape."
  (should (equal (mrt--reflow (mrt--lines "## 9. A ^a" "See §a\\:NO.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "See §a:1\\:NO.")))
  (should (equal (mrt--reflow (mrt--lines "## A ^u" "See §u\\:NO.") 40)
                 (mrt--lines (concat "## A" (make-string 34 ?\s) "^u")
                             "See §u\\:NO.")))
  ;; An escape after an appellation ends the run just the same.
  (should (equal (mrt--reflow (mrt--lines "## 9. A ^a" "See §a:9\\:9.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "See §a:1\\:9."))))

(ert-deftest mrt-reference-dot-opening-an-appellation ()
  "Rule 3.5: a reference trailed by a dot and an identifier character
is left alone entire, numbered section or no.  A number emitted ahead
of such a dot would be consumed with the text after it by the next
reflow, which rule 0 forbids."
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "## B ^u"
                              "See §a.b, §a.b.c, §u.b, and §a.1.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             (concat "## B" (make-string 34 ?\s) "^u")
                             "See §a.b, §a.b.c, §u.b, and §a.1."))))

(ert-deftest mrt-reference-dot-is-punctuation-where-nothing-follows ()
  "Rule 3.5 bites only on a dot an appellation character follows.  A
sentence closed by a reference takes its number as ever."
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "See §a. And §a.  Or §a." "See §a.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "See §a:1. And §a:1.  Or §a:1." "See §a:1."))))

(ert-deftest mrt-reference-dot-draws-no-log ()
  "Rule 3.5: the match is no reference, so it is never resolved and an
undefined anchor behind one is not reported."
  (let ((log (mrt--log-of (mrt--lines "## 9. A ^a" "See §bogus.b and §a.b.") 40)))
    (should-not (string-match-p "undefined anchor" log))
    (should-not (string-match-p "NOREF" log))))

(ert-deftest mrt-reference-dot-is-idempotent ()
  "Rule 0: each dotted case is a fixed point, first reflow and after.
This is the regression the rule exists for: `\\=§ab.y' once yielded
`\\=§ab:2.y', whose whole appellation the next reflow consumed, losing
the text after the dot."
  (dolist (body '("x §ab.y" "See §a.b.c." "§a.1 and §ab.2.3" "§a.§ab"
                  "§a:1.b" "§a. §ab." "§a.b:1"))
    (let ((once (mrt--reflow
                 (mrt--lines "## 9. A ^a" "### 9. B ^ab" body) 40)))
      (should (equal (mrt--reflow once 40) once)))))

(ert-deftest mrt-reference-dot-then-section-mark-still-resolves ()
  "A section mark opens no appellation, so the dot before one is
ordinary punctuation and both references take their numbers."
  (should (equal (mrt--reflow (mrt--lines "## 9. A ^a" "## 9. B ^b" "§a.§b") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             (concat "## 2. B" (make-string 31 ?\s) "^b")
                             "§a:1.§b:2"))))

(ert-deftest mrt-reference-punctuation-survives ()
  "Rule 3.4: punctuation outside the appellation class ends the run."
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "See §a:9, §a:9; §a:9) and §a:9.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "See §a:1, §a:1; §a:1) and §a:1."))))

(ert-deftest mrt-reference-colon-before-other-text ()
  "Rule 3.4: a colon followed by a character opening no appellation
opens none itself.  A dot may lie within an appellation but cannot
open one."
  (should (equal (mrt--reflow (mrt--lines "## 9. A ^a" "See §a:(x) and §a:.y.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "See §a:1:(x) and §a:1:.y."))))

(ert-deftest mrt-reference-appellations-are-idempotent ()
  "Rule 0: each of the colon cases is a fixed point."
  (dolist (body '("See §a:1:2:3, §a: Text, §a\\:NO, §a:9, and §a:(x)."
                  "See §u:1:2, §u: Text, and §u\\:NO."))
    (let ((once (mrt--reflow
                 (mrt--lines "## 9. A ^a" "## B ^u" body) 40)))
      (should (equal (mrt--reflow once 40) once)))))

(ert-deftest mrt-masked-reference-keeps-its-appellations ()
  "A masked reference is left whole, run of appellations and all."
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "Code `§a:1:2` and §a:1:2.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "Code `§a:1:2` and §a:1."))))

(ert-deftest mrt-reference-unnumbered-is-idempotent ()
  "Rule 0: the reduced reference is itself a fixed point."
  (let ((once (mrt--reflow (mrt--lines "## A ^u" "See §u:NONUM.") 40)))
    (should (equal (mrt--reflow once 40) once))))

(ert-deftest mrt-unnumbered-anchor-is-accepted ()
  "Section 3, Anchor: an unnumbered section's anchor is no defect.
Nothing is logged, for the heading or for the references to it, and a
document whose only peculiarity is such an anchor is left wholly alone."
  (let* ((doc (mrt--lines (mrt--justified "## A" "u" 40)
                          "See §u, §u, and §u."))
         (log (mrt--log-of doc 40)))
    (should-not (string-match-p "unnumbered" log))
    (should-not (string-match-p "NONUM" log))
    (should (string-match-p "markdown-reflow: no changes" log))
    (should (equal (mrt--reflow doc 40) doc))))

(ert-deftest mrt-duplicated-anchor-logged-at-its-heading ()
  "Section 3, Anchor: the redefinition is logged, not each reference."
  (let ((log (mrt--log-of
              (mrt--lines "## 9. A ^d" "## 9. B ^d" "See §d, §d, and §d.") 40)))
    (should (string-match-p "line 2: anchor defined multiple times: \\^d" log))
    (should-not (string-match-p "line 3: .*duplicat" log))
    (should-not (string-match-p "reference to duplicated anchor" log))))

(ert-deftest mrt-duplicate-logged-though-unreferenced ()
  "Section 3, Anchor: a redefinition is logged whether or not anything
names it."
  (should (string-match-p "line 2: anchor defined multiple times: \\^d"
                          (mrt--log-of (mrt--lines "## 9. A ^d" "## 9. B ^d") 40))))

(ert-deftest mrt-dupe-wins-over-an-absent-number ()
  "Rule 3.3: a duplicated anchor yields DUPE whether or not the section
it names is numbered, and either way round.  The absent number itself
draws no log."
  (dolist (case '(("## 9. A ^d" "## B ^d")
                  ("## A ^d" "## 9. B ^d")
                  ("## A ^d" "## B ^d")))
    (let ((log (mrt--log-of
                (mrt--lines (nth 0 case) (nth 1 case) "See §d.") 40)))
      (should (string-match-p "line 2: anchor defined multiple times: \\^d" log))
      (should-not (string-match-p "unnumbered" log))
      (should-not (string-match-p "line 3: reference" log))
      (should (string-match-p "See §d\\. -> See §d:DUPE\\." log)))))

(ert-deftest mrt-reference-trailing-dot ()
  "A reference is agnostic to a trailing dot, which is left alone."
  (should (equal (mrt--reflow
                  (mrt--lines "## 1. First" "## 5. Second ^p" "Ref §p:9." "Ref §p:9")
                  40)
                 (mrt--lines "## 1. First"
                             (concat "## 2. Second" (make-string 26 ?\s) "^p")
                             "Ref §p:2." "Ref §p:2"))))

(ert-deftest mrt-reference-in-heading-title ()
  "Rule 4: renumbering, then references, then justification."
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "## 9.9 B, see §a ^b") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             (concat "## 2. B, see §a:1" (make-string 21 ?\s)
                                     "^b")))))


;;; Code blocks

(ert-deftest mrt-fenced-block-masks ()
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "" "```" "## 7. Not a heading ^x"
                              "See §a." "```" "" "Live §a." "") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "" "```" "## 7. Not a heading ^x"
                             "See §a." "```" "" "Live §a:1." ""))))

(ert-deftest mrt-fence-indented-three-columns ()
  "A fence may be indented up to three columns."
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "   ```" "   See §a." "   ```"
                              "Live §a.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "   ```" "   See §a." "   ```" "Live §a:1."))))

(ert-deftest mrt-fence-indented-four-columns-in-a-paragraph ()
  "Indented four columns it is no fence, and interrupts no paragraph."
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "" "Paragraph:" "    ```" "    See §a.")
                  40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "" "Paragraph:" "    ```" "    See §a:1."))))

(ert-deftest mrt-fence-indented-with-a-tab ()
  "A tab indents four columns, so the line opens no fence."
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "" "\t```" "\tSee §a." "" "Live §a.")
                  40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "" "\t```" "\tSee §a." "" "Live §a:1."))))

(ert-deftest mrt-closing-fence-bears-no-info-string ()
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "" "```" "See §a." "``` js"
                              "Still §a." "```" "" "Live §a.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "" "```" "See §a." "``` js"
                             "Still §a." "```" "" "Live §a:1."))))

(ert-deftest mrt-backtick-info-string-opens-no-fence ()
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "" "``` a`b" "See §a.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "" "``` a`b" "See §a:1."))))

(ert-deftest mrt-tilde-info-string-admits-backticks ()
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "" "~~~ ```" "See §a." "~~~"
                              "Live §a.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "" "~~~ ```" "See §a." "~~~" "Live §a:1."))))

(ert-deftest mrt-longer-fence-required-to-close ()
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "" "````" "See §a." "```"
                              "Still §a." "````" "Live §a.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "" "````" "See §a." "```"
                             "Still §a." "````" "Live §a:1."))))

(ert-deftest mrt-unpaired-fence-masks-to-end ()
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "" "```" "See §a." "Still §a.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "" "```" "See §a." "Still §a."))))

(ert-deftest mrt-unpaired-fence-is-logged ()
  "Section 3, Code blocks: an unpaired fence is logged with a warning,
against the line that opened it."
  (let ((log (mrt--log-of
              (mrt--lines "## 9. A" "" "```" "See §a." "Still §a.") 40)))
    (should (string-match-p "line 3: unpaired fence" log))
    (should (string-match-p "1 problem logged" log))))

(ert-deftest mrt-indented-block-after-a-blank-line ()
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "" "    See §a." "" "Live §a.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "" "    See §a." "" "Live §a:1."))))

(ert-deftest mrt-indented-block-after-a-heading ()
  "A heading is no paragraph, so an indented block may follow it directly."
  (should (equal (mrt--reflow (mrt--lines "## 9. A ^a" "    See §a.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "    See §a."))))

(ert-deftest mrt-indented-block-interrupts-no-paragraph ()
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "" "Paragraph:" "    See §a.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "" "Paragraph:" "    See §a:1."))))

(ert-deftest mrt-indented-block-spans-blank-lines ()
  "Interior blank lines do not end an indented block."
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "" "    See §a." "" "    Still §a."
                              "" "Live §a.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "" "    See §a." "" "    Still §a."
                             "" "Live §a:1."))))


;;; Inline code

(ert-deftest mrt-inline-code-masks ()
  (should (equal (mrt--reflow (mrt--lines "## 9. A ^a" "Code `§a` and §a.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "Code `§a` and §a:1."))))

(ert-deftest mrt-inline-code-arity-matched ()
  "A span closes on a backtick string of exactly equal length."
  (should (equal (mrt--reflow (mrt--lines "## 9. A ^a" "Code ``§a`` and §a.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "Code ``§a`` and §a:1.")))
  (should (equal (mrt--reflow (mrt--lines "## 9. A ^a" "A `§a`` live.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "A `§a:1`` live."))))

(ert-deftest mrt-unmatched-backtick-is-text ()
  (should (equal (mrt--reflow (mrt--lines "## 9. A ^a" "A ` backtick and §a.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "A ` backtick and §a:1."))))

(ert-deftest mrt-inline-code-crosses-lines ()
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "Start `code" "§a masked` end.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "Start `code" "§a masked` end."))))

(ert-deftest mrt-inline-code-crosses-no-blank-line ()
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "Start `code" "" "§a live` end.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "Start `code" "" "§a:1 live` end."))))

(ert-deftest mrt-inline-code-crosses-no-heading ()
  (should (equal (mrt--reflow
                  (mrt--lines "Text with ` backtick" "## 9. A ^a"
                              "§a live ` here.") 40)
                 (mrt--lines "Text with ` backtick"
                             (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "§a:1 live ` here."))))

(ert-deftest mrt-escaped-backtick-opens-no-span ()
  (should (equal (mrt--reflow
                  (mrt--lines "## 9. A ^a" "A \\` and §a live ` here.") 40)
                 (mrt--lines (concat "## 1. A" (make-string 31 ?\s) "^a")
                             "A \\` and §a:1 live ` here."))))

(ert-deftest mrt-anchor-in-inline-code-is-no-anchor ()
  "A caret within inline code defines no anchor.  Note that the closing
backtick is what the anchor pattern balks at, an identifier running to
the end of its line: an anchor cannot in fact be masked, and the check
in `markdown-reflow--analyze' stands against a widening of the
pattern rather than against any document writable today."
  (should (equal (mrt--reflow (mrt--lines "## 9. A `^a`" "See §a.") 40)
                 (mrt--lines "## 1. A `^a`" "See §a:NOREF."))))


;;; The buffer

(ert-deftest mrt-point-is-left-where-it-was ()
  (with-temp-buffer
    (insert "## 9. Heading\nSome text here.\n")
    (setq fill-column 72)
    (goto-char (point-min))
    (forward-line 1)
    (forward-char 5)
    (let ((position (point))
          (inhibit-message t))
      (markdown-reflow)
      (should (= (point) position))
      (should (equal (buffer-substring-no-properties (point-min) (point-max))
                     "## 1. Heading\nSome text here.\n")))))

(ert-deftest mrt-whole-buffer-despite-narrowing ()
  (with-temp-buffer
    (insert "## 9. First\n## 9. Second\n")
    (setq fill-column 72)
    (narrow-to-region (point-min) (+ (point-min) 12))
    (let ((inhibit-message t))
      (markdown-reflow))
    (widen)
    (should (equal (buffer-substring-no-properties (point-min) (point-max))
                   "## 1. First\n## 2. Second\n"))))

(ert-deftest mrt-trailing-newline-preserved ()
  (should (equal (mrt--reflow "## 9. A\n") "## 1. A\n"))
  (should (equal (mrt--reflow "## 9. A") "## 1. A")))

(ert-deftest mrt-empty-and-plain-buffers ()
  (should (equal (mrt--reflow "") ""))
  (should (equal (mrt--reflow "Just some prose.\n") "Just some prose.\n")))

(ert-deftest mrt-read-only-buffer-is-refused ()
  "A read-only buffer is left alone and the refusal is immediate."
  (with-temp-buffer
    (insert "## 9. A\n")
    (setq buffer-read-only t)
    (should-error (markdown-reflow) :type 'buffer-read-only)
    (should (equal (buffer-string) "## 9. A\n"))))

(ert-deftest mrt-width-falls-back-where-fill-column-is-nil ()
  "`fill-column' nil disables filling rather than naming a width, so
the Emacs default of 70 stands in for it."
  (with-temp-buffer
    (insert "## 9. A ^a")
    (setq fill-column nil)
    (let ((markdown-reflow-width nil)
          (inhibit-message t))
      (markdown-reflow))
    (should (= 70 (length (buffer-string))))))

(ert-deftest mrt-single-undo-unit ()
  "Every change of one reflow lies before the same undo boundary."
  (with-temp-buffer
    (buffer-enable-undo)
    (insert "## 9. A\n### 9. B\n")
    (setq fill-column 72)
    (undo-boundary)
    (let ((inhibit-message t))
      (markdown-reflow))
    (should (equal (buffer-string) "## 1. A\n### 1.1 B\n"))
    (let ((entries buffer-undo-list)
          (changes 0))
      (while (car entries)
        (setq changes (1+ changes)
              entries (cdr entries)))
      ;; Changes were recorded, the boundary follows them all, and the
      ;; insertion of the text lies beyond it.
      (should (> changes 0))
      (should (null (car entries)))
      (should (cdr entries)))))

(ert-deftest mrt-changes-are-logged ()
  (let ((log (mrt--log-of "## 9. A ^a\nSee §bogus.\n")))
    (should (string-match-p "markdown-reflow: line 2: reference to undefined anchor"
                            log))
    (should (string-match-p "markdown-reflow: line 1: ## 9\\. A \\^a ->" log))))

(ert-deftest mrt-summary-counts-the-work ()
  "The summary tallies headings, references, anchors, and problems."
  (should (string-match-p
           (concat "11 headings renumbered, 8 references updated, "
                   "6 anchors justified, 3 problems logged")
           (mrt--log-of mrt--worked-input))))

(ert-deftest mrt-nothing-to-do-is-reported ()
  ;; The reflowed fixture still holds the anchor and reference errors
  ;; it exercises, so only the changes are absent.
  (should (string-match-p
           "0 headings renumbered, 0 references updated, 0 anchors justified"
           (mrt--log-of mrt--worked-output)))
  ;; With nothing at all to report the summary says so.
  (should (string-match-p "markdown-reflow: no changes"
                          (mrt--log-of "## 1. A\nJust prose.\n"))))

;;; The project's own documents

(defconst mrt--directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Where this file and the documents beside it live.")

(ert-deftest mrt-project-documents-are-fixed-points ()
  "Rule 0: the project's own Markdown is already reflowed.
The documents carry the notation they define, so a change to either
that leaves them unreflowed is a change whose examples no longer
match the implementation."
  (dolist (name '("README.md" "markdown-reflow.md"))
    (let ((path (expand-file-name name mrt--directory)))
      (should (file-readable-p path))
      (let ((text (with-temp-buffer
                    (insert-file-contents path)
                    (buffer-string))))
        (should (equal (mrt--reflow text 72) text))))))

(ert-deftest mrt-log-is-isolated-per-run ()
  "The log helper reports this run's work, not an earlier run's."
  (mrt--log-of mrt--worked-input)
  (let ((log (mrt--log-of "## 1. A\n")))
    (should-not (string-match-p "headings renumbered" log))
    (should (string-match-p "markdown-reflow: no changes" log))))

(provide 'markdown-reflow-test)

;;; markdown-reflow-test.el ends here

(when noninteractive
  (ert-run-tests-batch-and-exit))
