import { EditorView } from "codemirror";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { tags } from "@lezer/highlight";

// Override CodeMirror's base UI and fallback highlighter. CSS variables change
// with the document theme without replacing the editor, selection or undo stack.
export const editorTheme = [
  EditorView.theme({
    "&": {color: "var(--ink)", backgroundColor: "var(--panel)"},
    "&.cm-focused": {outline: "2px solid var(--accent)"},
    ".cm-content": {caretColor: "var(--ink)"},
    ".cm-cursor, .cm-dropCursor": {borderLeftColor: "var(--ink)"},
    ".cm-selectionBackground, &.cm-focused > .cm-scroller > .cm-selectionLayer .cm-selectionBackground": {backgroundColor: "var(--selection)"},
    ".cm-activeLine, .cm-activeLineGutter": {backgroundColor: "var(--active-line)"},
    ".cm-gutters": {backgroundColor: "var(--paper)", color: "var(--muted)", borderColor: "var(--line)"},
    ".cm-panels, .cm-tooltip": {backgroundColor: "var(--paper)", color: "var(--ink)", borderColor: "var(--line)"},
    ".cm-panels-top": {borderBottomColor: "var(--line)"},
    ".cm-panels-bottom": {borderTopColor: "var(--line)"},
    ".cm-tooltip-section:not(:first-child)": {borderTopColor: "var(--line)"},
    ".cm-tooltip-arrow": {display: "none"},
    ".cm-button": {background: "var(--panel)", color: "var(--ink)", borderColor: "var(--line)"},
    ".cm-button:active": {background: "var(--selection)"},
    ".cm-textfield": {backgroundColor: "var(--panel)", color: "var(--ink)", borderColor: "var(--line)"},
    ".cm-searchMatch, .cm-selectionMatch, .cm-snippetField": {backgroundColor: "var(--match)"},
    ".cm-searchMatch-selected": {backgroundColor: "var(--selection)"},
    ".cm-matchingBracket": {backgroundColor: "var(--bracket)"},
    ".cm-nonmatchingBracket": {backgroundColor: "var(--match)", outline: "1px solid var(--error)"},
    ".cm-specialChar, .cm-invalidchar": {color: "var(--error)"},
    ".cm-foldPlaceholder": {backgroundColor: "var(--paper)", color: "var(--muted)", borderColor: "var(--line)"},
    ".cm-placeholder": {color: "var(--muted)"},
    ".cm-tooltip-autocomplete ul li[aria-selected]": {backgroundColor: "var(--accent)", color: "var(--accent-ink)"},
    ".cm-tooltip-autocomplete-disabled ul li[aria-selected]": {backgroundColor: "var(--selection)", color: "var(--ink)"},
    ".cm-tooltip-autocomplete completion-section": {borderBottomColor: "var(--line)", opacity: 1},
    ".cm-completionIcon, .cm-completionListIncompleteTop:before, .cm-completionListIncompleteBottom:after": {opacity: 1},
    ".cm-snippetFieldPosition": {borderLeftColor: "var(--muted)"},
    ".cm-trailingSpace": {backgroundColor: "var(--match)"},
    ".cm-highlightSpace, .cm-highlightTab": {backgroundImage: "none", textDecoration: "underline", textDecorationColor: "var(--muted)"},
    ".cm-diagnosticAction": {backgroundColor: "var(--accent)", color: "var(--accent-ink)"},
    ".cm-lintRange": {backgroundImage: "none", textDecoration: "underline wavy var(--error)"},
    ".cm-lintRange-active, .cm-panel.cm-panel-lint ul [aria-selected]": {backgroundColor: "var(--selection)", color: "var(--ink)"}
  }),
  syntaxHighlighting(HighlightStyle.define([
    {tag: [tags.keyword, tags.operator, tags.atom, tags.bool, tags.null], color: "var(--accent)"},
    {tag: [tags.string, tags.regexp], color: "var(--syntax-string)"},
    {tag: [tags.number, tags.typeName, tags.className, tags.attributeName], color: "var(--syntax-number)"},
    {tag: [tags.comment, tags.meta], color: "var(--muted)"},
    {tag: [tags.heading, tags.strong], fontWeight: "bold"},
    {tag: tags.emphasis, fontStyle: "italic"},
    {tag: tags.link, color: "var(--accent)", textDecoration: "underline"},
    {tag: tags.invalid, color: "var(--error)"}
  ]))
];
