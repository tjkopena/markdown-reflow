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
maintenance of section numbering, references, and presentation.


## 1. Specification

Markdown sections and reflow are defined in
[markdown-reflow.md](markdown-reflow.md).


## 2. Implementations

### 2.1 Emacs

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

However many lines it touches, the reflow is one command and so one
undo unit: a single `C-_` takes the whole of it back.

References to anchors in other documents, such as
`§notes.md:intro:1`, are resolved relative to the directory of the
file the buffer visits.  Each such document is read from disk, never
altered, and its sections numbered as reflow would number them.  A
reference to a document that cannot be read, or from a buffer visiting
no file, is left alone and logged.

The preferred line width is `markdown-reflow-width` and tab stops are
`tab-width`.  The four-column tab stops by which GFM measures block
structure indentation are fixed and do not follow `tab-width`.

`markdown-reflow-width` defaults to nil, which follows `fill-column`,
so that reflow honors whatever width the buffer is already filled to.
Set it where anchors are to be justified to a width of their own:

```elisp
(setq markdown-reflow-width 72)
```

#### Test Cases

Test cases for the Emacs implementation are available in
[markdown-reflow-test.el](markdown-reflow-test.el) and may be
executed in batch mode:

```sh
emacs -Q --batch -l markdown-reflow-test.el
```

The suite covers all three normative conformance fixtures of the
specification, every transformation rule, code block and inline code
masking, and the reflow of this file and the specification themselves,
which carry the notation they define and so must already be reflowed.


## 3. License

Copyright (C) 2026 tjkopena.

Markdown reflow is free software, distributed under the terms of the
GNU General Public License, either version 3 or (at your option) any
later version.  See [LICENSE](LICENSE).
