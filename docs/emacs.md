# prinbox for Emacs

The pull requests waiting on you, in a `tabulated-list` buffer, over the `prinbox` command. Requires Emacs 29.1
and prinbox 0.7.0 or later (`brew install creeonix/tap/prinbox-cli`, signed in through `gh auth login`).

## Install

```elisp
(use-package prinbox
  :vc (:url "https://github.com/creeonix/prinbox" :rev :newest)
  :commands (prinbox prinbox-mode-line-mode))
```

or `M-x package-vc-install RET https://github.com/creeonix/prinbox RET`. The repository is the package:
`prinbox.el` sits at its root.

## Use

`M-x prinbox` opens `*prinbox*`: the cache at once, then a refresh in the background. Columns: Section, #, Title,
Repository, Reason, Age, Flags (`new`, `draft`, `snoozed`, `stack i/n`); rows in the popover's order.

| Key | Does |
|---|---|
| `RET`, `b` | open the pull request with `browse-url`; on a `+N more on GitHub` line, the section on GitHub |
| `s` | snooze it until something happens on it (a push, a reply in your thread, a new review request) |
| `u` | wake it |
| `g`, `G` | fetch now |
| `y`, `w` | copy the URL `RET` would open |
| `M-n`, `M-p` | the first row of the next section; of this one, or the previous one |
| `a` | show or hide the Reviewed section (`prinbox-all`), then fetch |
| `n`, `p`, `q`, `?` | the usual list keys: next, previous, bury the buffer, describe the mode |

The keys follow Emacs list modes: `b` and `G` as in Elfeed (browse, fetch), `y` as in Elfeed's copy link, `M-n` and
`M-p` as in Magit's sibling sections, and `s`/`u` as a do/undo pair, like Magit's stage and unstage.

The header line reads `8 waiting on you · updated 14:02 · 4 new`, with your default repositories appended when
some are set in PRInbox, and the error line when the last fetch failed. A snooze made here shows in the menu bar
and the popover within a second, and the other way round. Enter on a row whose diff moved since your review opens
GitHub's diff since that review.

## Options

| Custom | Default | Meaning |
|---|---|---|
| `prinbox-command` | `"prinbox"` | the executable |
| `prinbox-section-separator` | `nil` | between sections: `rule` (a line naming the section), `blank`, or nil |
| `prinbox-section-repeat-label` | `show` | the section label on a section's later rows: `show`, `dim` or `hide` |
| `prinbox-section-faces` | `nil` | the face of each section's label by kind; `prinbox-section-kind-faces` gives one color per section |
| `prinbox-max-age` | `60` | the buffer serves the cache when GitHub confirmed it within this many seconds |
| `prinbox-all` | `nil` | list every pull request you reviewed |
| `prinbox-rows` | `nil` | rows per section before `+N more on GitHub`; nil keeps the command's 8 (needs a command with `--rows`) |
| `prinbox-poll-seconds` | `0` | seconds between background refreshes for the mode line; 0 is off |

## Mode line

`(prinbox-mode-line-mode 1)` adds ` PR:8` to the mode line (nothing when nothing waits, `PR:!` or `PR:!8` after a
failed fetch) and, with `prinbox-poll-seconds` set, keeps it fresh.

## When something is wrong

| What you see | Why |
|---|---|
| `prinbox not found: brew install creeonix/tap/prinbox-cli` | the command is not on Emacs's `exec-path`; set `prinbox-command` |
| the sign-in steps in place of the rows | gh is signed out: `gh auth login` |
| `· GitHub did not answer in time` in the header line | the fetch failed; the rows are the last known ones |
| `prinbox prints JSON version N; this plugin reads version 1` | the command is newer than the package: update it |

The package reads only what the command prints: titles, logins, URLs, counts and dates, never comment text.
