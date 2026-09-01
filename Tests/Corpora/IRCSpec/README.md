# IRC specification corpora

Test vectors that come from outside this project, used by the
`IRCSpec*Tests` suites to check Glasstual's IRC implementation against the
specifications rather than against itself.

## parser-tests

`parser-tests/` vendors https://github.com/ircdocs/parser-tests at commit
`75b4c7e` (2023-05-29): the `msg-split`, `msg-join`, `userhost-split`,
`mask-match` and `validate-hostname` vectors. The upstream corpus is
dedicated to the public domain under CC0 1.0; the dedication is kept
verbatim in `parser-tests/LICENSE`.

The committed JSON files are the test inputs. They are copied into the test
bundle by the `GlasstualTests` target and read through `IRCSpecCorpus`. Update
them directly from the matching upstream release; the repository does not keep
a second YAML copy or a format-conversion script.
