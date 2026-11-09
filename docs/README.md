# Huck documentation

| Folder | What's in it |
|---|---|
| [`architecture/`](architecture/) | How a piece of the app works today, walked through end to end. |
| [`decisions/`](decisions/) | Architecture decision records: a rule we adopted, why, and what it applies to. Numbered in the order they were made; never renumbered. |
| [`proposals/`](proposals/) | Designs written before the work. Kept as written, so file paths in them reflect the code at the time. |

The networking layer documents itself in [`Huck/Networking/README.md`](../Huck/Networking/README.md), next to the code.

## Writing a decision record

Copy the header of an existing record (`Status`, `Date`, `Applies to`), take the next number, and keep it short: the rule, the reasoning, and the cases it covers. To reverse a decision, add a new record that supersedes it and set the old one's status to `Superseded by NNNN`.
