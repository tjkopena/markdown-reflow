# Markdown Reflow

_Markdown sections_ are a convention for anchoring and referencing
nested numbered section headings in Markdown documents, e.g.:

```markdown
# My Software

## 1. Introduction                                                ^intro

## 2. Specification
### 2.1 Limitations                                              ^limits

## 3. Implementation
### 3.1 INTERCAL

As described in §intro:1 and motivated by blah blah (§limits:2.1)...
```

The notation is designed to facilitate _Markdown reflow_, automatic
maintenance as specified in this document of section numbering,
references, and presentation via text editor modules that:

* Reflow dot-notation section heading enumeration.
* Right-justify careted anchors on section headings.
* Update section mark references to those anchors.

For example, the input:
```markdown
# My Document

Some text

## Copyright

More text

## 2. Notes
### 2.2 From A Pagan Nation ^pagans

Great content heah

## 4. Gibberish
Four score and seven years ago (§pagans).
```

Results in the following (assuming 72 column configuration):
```markdown
# My Document

Some text

## Copyright

More text

## 1. Notes
### 1.1 From A Pagan Nation                                      ^pagans

Great content heah

## 2. Gibberish
Four score and seven years ago (§pagans:1.1).
```

Numbering follows heading depth, starting from `##`, so the single-hash
document title is skipped. `## Copyright` carries no number, so it is
left alone and does not consume a slot in the ordering.  The section
anchor has been right-justified and the reference appended with the
appropriate section number.


## 1. Editor Implementations

### 1.1 Emacs

An Emacs implementation of Markdown reflow is in
[markdown-reflow.el](markdown-reflow.el).

Load the code from the file or manually include it in your `.emacs`.

Run `M-x markdown-reflow` in the buffer. The function operates over
the whole buffer, not the region, and leaves point where it was.
Narrowing is disregarded, section numbering being a property of the
document as a whole.

To bind the function, apply `global-set-key` to a sequence reserved for
users, e.g. `C-c` followed by a plain letter:

```elisp
(global-set-key (kbd "C-c m") #'markdown-reflow)
```

Note that `C-c` followed by `<`, `>`, `{`, `}`, `:`, `;`, a digit, or a
control character is reserved for major modes and will be shadowed and
not invoke the `markdown-reflow` function in modes that claim it.

All changes made are logged to the \*Messages\* buffer and a summary
reported to the echo area.

The edit is a single undo unit only if you have not touched the buffer
in between; `C-_` may need repeating on a large document.

The preferred line width is defined by `fill-column` and the tab stops
of rule 2.3 by `tab-width`.  The four-column tab stops by which GFM
measures the indentation defining block structure are fixed and do not
follow `tab-width`.

#### Test Cases

Test cases for the Emacs implementation are available in
[markdown-reflow-test.el](markdown-reflow-test.el) and may be
executed in batch mode:

```sh
emacs -Q --batch -l markdown-reflow-test.el
```


## 2. Specification

Markdown sections and reflow rules are defined here.

The baseline Markdown variant on which this specification is built is
[GitHub Flavored Markdown](https://github.github.com/gfm/) (GFM), which
in turn is defined on top of [CommonMark](https://commonmark.org/).

### 2.1 Definitions

This section defines terms and concepts for Markdown sections.

The regexes below are PCRE2 and are applied per line, as with the `m`
modifier; `.` never matches a newline.  UTF-8 mode is assumed so that
`.` counts characters rather than bytes.  Code blocks and inline code
are masked before regexes are applied; being line-local, regexes cannot
themselves make those exclusions.  The regexes are normative as to
behavior, and engines providing neither branch reset nor lookahead,
e.g., Emacs regex, must decompose them preserving that behavior.

**Preferred line width.**  The number of text columns the document's
lines ideally fall within, and to which anchors are right-justified.
Commonly 80 columns in terminals, 72 in IETF RFCs, and 70 by default in
Emacs.  Setting this parameter is implementation dependent.

**Section.**  An organizational region of the text, indicated in
Markdown by a header line opened with two to six hash marks (`#`),
optionally followed by a title separated by whitespace.  As in GFM, a
run of seven or more hash marks opens no heading.

**Depth.**  The nesting level of the section heading, corresponding to
one less than the number of hash marks: `##` is level 1, `###` is level
2, and so on to `######` at level 5.  A single hash (`#`) is ignored for
numbering purposes.

**Dot notation.**  A series of integers separated by dots (`.`), such as
`2`, `2.1`, or `1.2.3.4`.

**Numbered section heading.**  The opening of a section assigned a
tiered numeric appellation: A line beginning with two to six hash marks
(`#`), whitespace, then a dot-notation section number.  If the section
number is single-component it MUST be followed by a trailing dot.
Multi-component section numbers followed by a trailing dot are
recognized but the trailing dot MUST NOT be emitted.  Regex:

```
^(#{2,6})[ \t]+(?|([0-9]+(?:\.[0-9]+)+)\.?|([0-9]+)\.)(?=[ \t]|$)
```

Group 1 captures the hash marks, from which depth is determined, and
group 2 the dot-notation section number.  Renumbering replaces the whole
of the match: The hash marks and following whitespace are preserved, and
the canonical section number is emitted in place of the matched number
and its trailing dot where present.  Title text is never altered.

**Anchor.** A case-sensitive identifier used to unambiguously and
portably refer to a specific section, permitting characters
`[A-Za-z0-9_/#-]+`.  In-text designation of an anchor is made by closing
a section heading line with a caret (`^`) and the identifier.  Regex:

```
^(#{2,6})(?=[ \t])(?:.*[^ \t])?([ \t]+)\^([A-Za-z0-9_/#-]+)([ \t]*)$
```

Group 1 is the heading line hash marks.  Group 2 is whitespace to be
resized to right-justify the anchor to a configured preferred line width
(as defined by implementations).  Group 3 is the anchor identifier.
Group 4 is extraneous whitespace to delete.

Where a heading line bears more than one caret, the last is the anchor.

An anchor defined multiple times is logged as an error.

Anchors may be put on both numbered and unnumbered section headings.
Both contribute to detection of duplicated anchor identifiers.

**Reference.** A reference to a section via its anchor, denoted by a
section mark (`§`) followed by the anchor identifier and possibly a
colon (`:`) and either the section's dot-notation number or one of the
exception flags `NOREF`, `DUPE`, or `NONUM`. Regex:

```
§([A-Za-z0-9_/#-]+)(:(?:NOREF|DUPE|NONUM|[0-9]+(?:\.[0-9]+)*))?
```

Group 1 is the anchor identifier to reference.  Group 2 is the
dot-notation section number or exception flag to be replaced with a
correctly reflowed section number or exception flag (preceded by a
colon) for the referenced section.

Note that references including a section number are agnostic to a
trailing dot.  Both single- and multi-component section numbers may or
may not be followed by a trailing dot, e.g. for sentence punctuation.
For example, `§pagans:1.` reflowed to section 2.3 yields `§pagans:2.3.`

**Fences.**  Delimiter lines opening or closing a fenced code block: a
run of three or more backticks (```` ``` ````) or three or more tildes
(`~~~`), indented no more than three columns and followed by an optional
info string.  A backtick fence's info string MUST NOT contain a
backtick; a tilde fence's may hold any text.  A closing fence bears no
info string, only whitespace following its run.  Regexes:

```
Opening:  ^ {0,3}(?|(`{3,})([^`]*)|(~{3,})(.*))$
Closing:  ^ {0,3}(`{3,}|~{3,})[ \t]*$
```

Group 1 is the fence run, from which the fence character and length are
determined, and group 2 of the opening pattern the info string.  A line
matching both patterns opens a fenced block or closes an open one of the
same character and no greater length, closing taking precedence.

Indentation here and for indented code blocks is measured in display
columns with tabs expanded to four-column tab stops, so a line opening
with a tab is indented four columns and cannot be a fence.

**Code blocks.**  Code blocks are preformatted, uninterpreted text
designated by paired fences or by indentation of four or more columns.
The closing fence of a pair must match the opening fence in the
character used and be at least as great in length.  An unpaired fence
consumes the remainder of the document and is logged with a warning.
The info string on the opening line of a fence pair indicates the format
or language therein and has no impact on Markdown reflow.  Section
headings, anchors, and references are ignored within code blocks, as are
the fence lines themselves, so a section mark or hash mark carried by an
info string is inert.

An indented code block does not interrupt a paragraph: One begins only
at the start of the document or where the preceding line is blank, a
section heading, or part of a code block.  Interior blank lines do not
end it; it ends at the first non-blank line indented fewer than four
columns, and trailing blank lines are not part of it.

Fences take precedence over indentation: A line indented three or fewer
columns matching the fence pattern opens a fenced block even where an
indented code block could otherwise begin, and a line indented four or
more columns is never a fence.

**Inline Code.**  Short preformatted, uninterpreted text delimited by
backtick strings, ignored for anchors and references.  A backtick string
is a maximal run of backticks, neither preceded nor followed by a
backtick; a backslash-escaped backtick (`` \` ``) is not part of one.
Scanning left to right, a backtick string opens a code span which ends
at the next backtick string of exactly equal length.  Where there is no
such closer the opening backtick string is ordinary text and scanning
resumes immediately after it.

A code span never crosses a blank line, a code block boundary, or a
section heading line.  The regions within which spans are matched are
therefore the maximal runs of consecutive non-blank lines outside code
blocks, each ATX heading line (`^ {0,3}#{1,6}(?:[ \t]|$)`) constituting
a region of its own.

### 2.2 Deviations From GFM

Anchors and references are not GFM constructs at all; to GFM they are
ordinary text, which is what makes the notation portable.  Section
headings are GFM ATX headings, of which Markdown reflow recognizes close
to a subset.  The first three constructs below are left alone entirely:
They are never numbered, anchored, or justified, and their text is not
disturbed.  The entries that follow record where recognition of headings
and code blocks departs from GFM in either direction.

**Indented ATX headings.**  GFM permits an ATX heading to be indented
up to three spaces.  The heading regexes are anchored at column zero,
so an indented heading is inert.

**Setext headings.**  A title underlined with `=` or `-` is a GFM
heading but bears no hash marks and so has no depth.  Setext headings
are inert.

**Headings within containers.**  A heading inside a block quote
(`> ## Foo`) or a list item is preceded by its container's markers and
so does not match at column zero.  It is inert.

**ATX closing sequences.**  GFM permits a heading to close with a run
of hash marks.  Such a heading is numbered normally, but an anchor must
end its line, so `## 2. Foo ##` is renumbered while `## Foo ^x ##`
carries no anchor.

**Code block recognition.**  Fenced and indented code blocks follow GFM:
Fences are indented no more than three columns, a closing fence bears no
info string, a backtick fence's info string holds no backtick, and an
indented code block does not interrupt a paragraph.  What remains
unaligned is container structure.

**Containers.**  Indentation is measured from column zero rather than
relative to an enclosing block quote or list item, and container
prefixes (`>`, list markers) are not stripped.  Four-space indented
continuation text inside a list item, following a blank line, is
therefore a code block here where GFM would read it as text indented
only to its container's content; since the effect of a code
block is to leave its contents alone, that deviation is conservative.
The converse is not: A fence prefixed by a block quote marker is not
recognized at all, so the contents of a block-quoted fenced block are
processed as ordinary text, and a fenced block is not terminated by the
end of its container.

**Inline code spans.**  As in GFM, an inline code span may cross line
boundaries, and fences and code blocks are identified first with inline
code identified only in what remains.  Masking is applied to the
document text rather than line by line and so is not constrained by the
line-local regexes, but a span is confined to its region.  Regions are
bounded by blank lines, code block boundaries, and ATX heading lines
only; other leaf blocks---thematic breaks, HTML blocks,
setext underlines, table rows---do not bound a region, so a span may
cross one where GFM would not.

GFM's other extensions---tables, strikethrough, autolinks, task
lists---carry ordinary text and are processed normally.

### 2.3 Transformation Rules

The following rules specify the maintenance enacted by Markdown reflow.

0. Transformations are idempotent: Repeat performance changes nothing.

1. All dot-notation section headings are reflowed so the assigned
   numbering for each depth starts at 1, has no gaps, and is in order.

   1.1 Depth is always determined by the explicit hash marks and a
       document is always rooted at depth 1.  Implicit, skipped, levels
       start at 1 and consume a slot.
       * Example: If the first heading in a document is `####` it will
         be numbered 1.1.1.
       * Example: A `#####` heading directly under a `##` yields
         `1.1.1.1`, not `1.0.0.1`.
       * Example: Following `##### 1.1.1.1`, a subsequent `###` would be
         numbered 1.2, not 1.1.

   1.2 Additional single-hash headings after the first such declaration
       are logged with a warning and otherwise ignored.
       * Example:
       ```
       # Title
       ## 1. Introduction
       # Chapter 1
       ## 4. Content
       ```

       Yields:
       ```
       # Title
       ## 1. Introduction
       # Chapter 1
       ## 2. Content
       ```

   1.3 Unnumbered headings and headings with a leading bare integer but
       no trailing dot are inert: They are not given numbers and the
       counter is advanced only by numbered section headings.
       * Example: The `## Copyright` section is neither given a number
         nor counted, resulting in `## 1. Notes` versus `## 2. Notes`.
       * Example: `## 2024 Retrospective` is not a numbered section.

   1.4 A section heading number has exactly as many components as the
       heading's depth, and carries a trailing dot if and only if it is
       single-component.  Components and the trailing dot are added or
       cut as needed, as when a section is promoted or demoted.  Section
       numbers in the following examples are assumed correct in context.
       * Example: A depth 2 heading keeps two components and sheds any
         trailing dot:
         ```
         ### 2.1. Good Section
         ```

         Yields:
         ```
         ### 2.1 Good Section
         ```
       * Example: A depth 1 heading is reduced to one component and
         gains a trailing dot:
         ```
         ## 2.1 Ok Section
         ```

         Yields:
         ```
         ## 2. Ok Section
         ```

   1.5 Whitespace between section heading hash marks and the section
       number, as well as between the section number (including the
       trailing dot for a single-component number) and the title, is
       normalized to a single space.
       * Example:
         ```
         ##  2.    Ok Section
         ```

         Yields:
         ```
         ## 2. Ok Section
         ```

   1.6 Transitions to a deeper depth start a new counter for that deeper
       depth beginning at 1.
       * Example:
           ```
           ## 2. First Tier
           ### 2.3 First Point
           ### 2.6 Second Point
           ## 1. Back to First Tier
           ### 1.8 First Point
           ### 1.1 Second Point
           ```

         Yields:
           ```
           ## 1. First Tier
           ### 1.1 First Point
           ### 1.2 Second Point
           ## 2. Back to First Tier
           ### 2.1 First Point
           ### 2.2 Second Point
           ```

2. Anchors are right-justified to the configured preferred line width.
   * Example:
     ```
     ## 4. Conclusion ^conclusion
     ```

     With a preferred line width of 72 transforms to:
     ```
     ## 4. Conclusion                                             ^conclusion
     ```

   2.1 Any extraneous whitespace following the anchor is deleted.

   2.2 Any tabs or other whitespace immediately preceding the
       anchor is replaced with a number of spaces filling the line:
       ```
       max(<preferred line width> -
           <run start column, 0-based> -
           <anchor width excluding caret> -
           1,                        // Account for caret
           1)
       ```

   2.3 Widths are measured by display columns, not character counts (in
       Emacs this aligns with `fill-column`).  Note that an anchor
       identifier's width as display columns or characters is equivalent
       as the class holds only single-width characters.  Tab stops are a
       configured width inherited from the editor or otherwise given.

3. References are updated to include the dot-notation number for the
   section, separated from the anchor identifier by a colon.  This is
   done whether or not the reference originally included the number.
   * Example: `§pagans` and `§pagans:0.0.0` both become `§pagans:1.1`

   3.1 If the referenced anchor does not exist the appellation `NOREF`
       is given instead and the error logged.
       * Example: `§bogus` becomes `§bogus:NOREF`

   3.2 If the referenced anchor is defined multiple times then the
       appellation `DUPE` is given instead and the error logged.

   3.3 If the referenced anchor is defined on an unnumbered section the
       appellation `NONUM` is given instead and the error logged.  The
       `DUPE` error takes precedence over `NONUM` but both are logged.

4. Precedence over operations from greatest to least is: Section
   re-numbering, then references, then anchor justification.  This
   matters, e.g., in section headings combining multiple features and
   changes, such as updating both the number of its dot-notation
   components and appending a section number to a reference in the title
   then right-justifying an anchor.

### 2.4 Worked Example

The following is normative as a conformance fixture, exercising every
transformation rule and every exception flag.  Input under a preferred
line width of 72 with widths shown at left:

```
13  # My Document
19  ## Copyright ^legal
11  ## 2. Notes
27  ### 2.1 From A Pagan Nation
47  As discussed in §problematic, blah blah blah...
34  Also see §legal, §bogus, and §dup.
16  ## 4.9 Gibberish
72  ### 4.1 Anchored and full                                ^notes/gib1-a#b
33  ### 4.12. Two digits going to one
29  ### 4.1 Unjustified anchor ^x
88  ### 4.1 Much too much padding                                               ^problematic
74  ### 4.2 An overlong title that leaves no room at all for its anchor ^tight
33  ##### 9.9.9.9 Skipped levels ^dup
29  ### 9. Duplicated anchor ^dup
37  Masked and so untouched: `§bogus` and
 7  ~~~text
30  ## 7. Not a heading ^notanchor
29  See §problematic in here too.
 3  ~~~
```

Output:

```
13  # My Document
72  ## Copyright                                                      ^legal
11  ## 1. Notes
27  ### 1.1 From A Pagan Nation
51  As discussed in §problematic:2.4, blah blah blah...
51  Also see §legal:NONUM, §bogus:NOREF, and §dup:DUPE.
15  ## 2. Gibberish
72  ### 2.1 Anchored and full                                ^notes/gib1-a#b
31  ### 2.2 Two digits going to one
72  ### 2.3 Unjustified anchor                                            ^x
72  ### 2.4 Much too much padding                               ^problematic
74  ### 2.5 An overlong title that leaves no room at all for its anchor ^tight
72  ##### 2.5.1.1 Skipped levels                                        ^dup
72  ### 2.6 Duplicated anchor                                           ^dup
37  Masked and so untouched: `§bogus` and
 7  ~~~text
30  ## 7. Not a heading ^notanchor
29  See §problematic in here too.
 3  ~~~
```

Of note:

* `^legal` is on an unnumbered heading, so it is justified like any
  other anchor but `§legal` resolves to `NONUM`.
* `§bogus` names no anchor and resolves to `NOREF`; the occurrence in
  inline code on the penultimate paragraph is masked and untouched.
* `^dup` is defined twice, so `§dup` resolves to `DUPE`.  The trailing
  dot of the sentence is left alone, per the trailing dot agnosticism
  of references.
* `## 4.9` is reduced to the single component `2.` and `### 4.12.` is
  stripped of its trailing dot, while `### 9.` gains a second component
  and sheds its dot, per rule 1.4.
* `^tight` cannot be justified, as its heading already exceeds the
  preferred line width.  The padding is the floor of one space and the
  line is left over-width.
* The tilde fenced block masks a heading, an anchor, and a reference,
  none of which are numbered, justified, or resolved.
* `##### 9.9.9.9` skips depth 3, which starts at 1 and consumes a slot,
  yielding `2.5.1.1`.  The `###` that follows resumes the depth 2
  counter at `2.6`.

### 2.5 Code Block Fixture

The following is normative as a conformance fixture for the code block
and inline code definitions given above, exercising the cases in which
masking turns on a GFM distinction.  Input under a preferred line width
of 72 with widths shown at left, blank lines carrying a width of zero:

```
 9  # Fixture
 0
13  ## 2. Masking
22  ### 2.3 Anchored ^mask
 0
30  Text before an indented fence:
 7      ```
19      See §mask here.
 0
35      Indented code holding §mask and
 0
37      a second chunk, §mask masked too.
 0
18  Live again: §mask.
 0
 3  ```
28  fenced content, §mask masked
 6  ``` js
19  still masked, §mask
 3  ```
 0
 7  ``` a`b
31  Not a fence, so §mask resolves.
 0
44  An unmatched backtick ` ends this paragraph.
 0
18  Still live: §mask.
 0
22  ## 3. Odd ` in a title
 0
55  Live here: §mask, and then a backtick ` closes nothing.
```

Output:

```
 9  # Fixture
 0
13  ## 1. Masking
72  ### 1.1 Anchored                                                   ^mask
 0
30  Text before an indented fence:
 7      ```
23      See §mask:1.1 here.
 0
35      Indented code holding §mask and
 0
37      a second chunk, §mask masked too.
 0
22  Live again: §mask:1.1.
 0
 3  ```
28  fenced content, §mask masked
 6  ``` js
19  still masked, §mask
 3  ```
 0
 7  ``` a`b
35  Not a fence, so §mask:1.1 resolves.
 0
44  An unmatched backtick ` ends this paragraph.
 0
22  Still live: §mask:1.1.
 0
22  ## 2. Odd ` in a title
 0
59  Live here: §mask:1.1, and then a backtick ` closes nothing.
```

Of note:

* The four-space indented fence follows a paragraph line.  It opens no
  fenced block, being indented four columns, and no indented one, an
  indented code block not interrupting a paragraph.  It and the line
  beneath it are paragraph text, and the reference there is resolved
  despite the indentation.
* The indented code block that follows the blank line does begin, and
  the blank line within it does not end it: The reference in its second
  chunk is masked along with the first.  It ends at `Live again`, the
  first non-blank line indented fewer than four columns.
* The `` ``` js `` line bears an info string and so does not close the
  fenced block; the block runs to the bare fence two lines later and
  both references within are masked.
* The `` ``` a`b `` line is not an opening fence, a backtick fence's
  info string admitting no backtick.  It is paragraph text, as is the
  line beneath it, whose reference is resolved.  Its backtick strings of
  length three and one match nothing and are ordinary text.
* The unmatched backtick opens no code span, there being no backtick
  string of equal length remaining in its region, and the blank line
  that follows bounds the region regardless.  The reference in the next
  paragraph is untouched by it.
* The backtick in the `## 3.` title and the backtick in the paragraph
  beneath it are in separate regions, a heading line constituting a
  region of its own, so neither masks the reference between them.  The
  heading is renumbered with its title, backtick and all, left alone.
