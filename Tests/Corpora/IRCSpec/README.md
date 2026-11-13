# IRC specification corpora

`IRCSpec*Tests` uses the
[ircdocs/parser-tests](https://github.com/ircdocs/parser-tests) corpus at
commit `75b4c7e` to check IRC parsing against independent test vectors.

`parser-tests/` contains the `msg-split`, `msg-join`, `userhost-split`,
`mask-match` and `validate-hostname` JSON vectors. The upstream CC0 1.0
public-domain dedication is in [parser-tests/LICENSE](parser-tests/LICENSE).

The `GlasstualTests` target bundles the JSON files for `IRCSpecCorpus`.
Update them directly from upstream and record the source revision here.
