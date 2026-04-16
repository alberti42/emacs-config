# PR: Fix StringIndexOutOfBoundsException in MarkdownAnnotatedTextBuilder.addComment

## Title

Fix StringIndexOutOfBoundsException in addComment shadow offset mapping

## Summary

`MarkdownAnnotatedTextBuilder.addComment` crashes with a `StringIndexOutOfBoundsException` when processing programming language comments. The crash is caused by two independent off-by-one errors in the shadow offset mapping between `clearCode` (fed to the markdown parser) and `fullCode` (used for `substring()` calls). Together they can produce an overshoot of 2, as seen in the error below.

## Reproduction

The crash was observed when running ltex-ls-plus against an Emacs Lisp (`.el`) file with `lsp-ltex-plus` as the LSP client. The language ID is `"lisp"` and the comment prefix regex is `;;?`. The crash triggers during `textDocument/codeAction`:

```
SEVERE: Internal error: java.lang.StringIndexOutOfBoundsException: Range [72, 74) out of bounds for length 72
java.util.concurrent.CompletionException: java.lang.StringIndexOutOfBoundsException: Range [72, 74) out of bounds for length 72
    ...
Caused by: java.lang.StringIndexOutOfBoundsException: Range [72, 74) out of bounds for length 72
    at java.base/java.lang.String.substring(Unknown Source)
    at org.bsplines.ltexls.parsing.markdown.MarkdownAnnotatedTextBuilder.addMarkup(MarkdownAnnotatedTextBuilder.kt:102)
    at org.bsplines.ltexls.parsing.markdown.MarkdownAnnotatedTextBuilder.addComment(MarkdownAnnotatedTextBuilder.kt:164)
    at org.bsplines.ltexls.parsing.program.ProgramAnnotatedTextBuilder.addComment(ProgramAnnotatedTextBuilder.kt:98)
    at org.bsplines.ltexls.parsing.program.ProgramAnnotatedTextBuilder.addCode(ProgramAnnotatedTextBuilder.kt:51)
    at org.bsplines.ltexls.server.DocumentChecker.buildAnnotatedTextFragments(DocumentChecker.kt:100)
    at org.bsplines.ltexls.server.DocumentChecker.check(DocumentChecker.kt:316)
    at org.bsplines.ltexls.server.LtexTextDocumentItem.check(LtexTextDocumentItem.kt:424)
    at org.bsplines.ltexls.server.LtexTextDocumentItem.checkWithCache(LtexTextDocumentItem.kt:344)
    at org.bsplines.ltexls.server.LtexTextDocumentService.codeAction$lambda$1(LtexTextDocumentService.kt:189)
```

Although the crash was observed with Lisp, the bug affects **all programming languages** handled by `ProgramAnnotatedTextBuilder` (Java, C, Rust, Haskell, etc.), since they all delegate to `MarkdownAnnotatedTextBuilder.addComment`. Python is unaffected because it uses `RestructuredtextAnnotatedTextBuilder` instead.

## Root Cause Analysis

`MarkdownAnnotatedTextBuilder.addComment` builds two parallel strings from the comment's code segments and markup (comment-prefix) segments:

```kotlin
for ((index, markup) in markups.withIndex()) {
    fullCode += markup.first + code[index]
    clearCode += code[index] + "\n"
}
```

- `fullCode` reconstructs the original comment text (markups interleaved with code). It is assigned to `this.code` and used in all `substring()` calls.
- `clearCode` contains just the code segments separated by `"\n"`. It is fed to the flexmark markdown parser, whose AST node offsets are relative to `clearCode`.

A `shadowOffset` mechanism maps positions from `clearCode` coordinates back to `fullCode` coordinates. When visiting AST nodes, positions are computed as `node.offset + shadowOffset` and used to index into `fullCode`.

### Bug 1: Trailing `"\n"` in `clearCode` with no counterpart in `fullCode`

The loop unconditionally appends `"\n"` after every code segment, including the last one. This means `clearCode` always ends with a trailing `"\n"` that has no corresponding character in `fullCode`:

- `clearCode` length = sum(|code[i]|) + N
- `fullCode` length = sum(|markup[i]|) + sum(|code[i]|)

When the markdown parser produces a node whose `endOffset` reaches or crosses the position of that trailing `"\n"`, the shadow-offset-adjusted position exceeds `fullCode.length`, causing the `StringIndexOutOfBoundsException`.

Concretely, if the parser produces `endOffset = clearCode.length`, the mapped position becomes:

```
clearCode.length + shadowOffset = fullCode.length + 1
```

This is 1 past the end of `fullCode`.

### Bug 2: CRLF line endings not handled in `removeComment`

The `removeComment` method adjusts `shadowOffset` when crossing markup boundaries. It applies a `-1` correction when the markup text starts with `'\n'`, to account for the `"\n"` separator in `clearCode` that the markup replaces:

```kotlin
shadowOffset += if (shadowMarkup.first.firstOrNull() == '\n') {
    offset - 1
} else {
    offset
}
```

With CRLF line endings (`\r\n`), the inter-line markup starts with `'\r'`, not `'\n'`. The check fails, the `-1` correction is skipped, and `shadowOffset` overcounts by 1 for each CRLF line boundary.

### Combined effect

Bug 1 contributes +1 overshoot. Bug 2 contributes +1 per CRLF line boundary. In the observed crash, the combined overshoot was 2 (`Range [72, 74)` on a string of length 72), consistent with one trailing-newline mismatch plus one CRLF boundary.

## Fix

### Change 1: Do not append trailing `"\n"` to `clearCode` (line 154)

Only add `"\n"` between code segments, not after the last one:

```kotlin
for ((index, markup) in markups.withIndex()) {
    fullCode += markup.first + code[index]
    clearCode += code[index]
    if (index < markups.lastIndex) {
        clearCode += "\n"
    }
}
```

This ensures `clearCode` and `fullCode` stay aligned at the end. The markdown parser handles unterminated last lines identically (e.g., `"Hello\nWorld"` and `"Hello\nWorld\n"` produce the same AST).

### Change 2: Handle `'\r'` in `removeComment` (line 229)

Check for both `'\n'` and `'\r'` as line-break indicators:

```kotlin
shadowOffset += if (shadowMarkup.first.firstOrNull()?.let { it == '\n' || it == '\r' } == true) {
    offset - 1
} else {
    offset
}
```

## File changed

`src/main/kotlin/org/bsplines/ltexls/parsing/markdown/MarkdownAnnotatedTextBuilder.kt`

## Tests

All 206 existing tests pass after the fix, including:

- `ProgramAnnotatedTextBuilderTest` (13 tests) -- covers Java, Python, PowerShell, Julia, Lua, Haskell, SQL, Lisp, Matlab, Erlang, Fortran, Visual Basic, and Rust comment parsing.
- `MarkdownAnnotatedTextBuilderTest` (7 tests) -- covers core markdown-to-annotated-text conversion.

```bash
mvn test
# Tests run: 206, Failures: 0, Errors: 0, Skipped: 0
```
