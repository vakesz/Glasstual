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

The `.yaml` files are the upstream originals. The test bundle has no YAML
reader, so `convert-parser-tests.py` converts them to the `.json` files the
suites load. Both forms are committed; re-run the script after refreshing
the YAML:

    pip install pyyaml
    python3 Tests/Corpora/IRCSpec/convert-parser-tests.py

The JSON is copied into the test bundle by the `GlasstualTests` target (see
`project.yml`) and read back through `IRCSpecCorpus`.
