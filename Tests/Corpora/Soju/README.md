# soju bouncer-networks transcripts

`bouncer-networks.txt` holds registration transcripts for soju's
`soju.im/bouncer-networks` and `soju.im/bouncer-networks-notify`
capabilities, written from the
[specification](https://git.sr.ht/~emersion/soju/tree/master/item/doc/ext/bouncer-networks.md)
rather than captured from a live bouncer.

A transcript is a list of scenarios, each starting with `== name`. Within one:

- `S <line>` is a line the bouncer sends.
- `A` acknowledges every `CAP REQ` the session has sent so far.
- `C <line>` is the next line of interest the session must have sent:
  `CAP END` or a `BOUNCER` command.
- `#` starts a comment.

`SojuTranscriptTests` replays each scenario through a session and checks the
`C` lines in order. The tests read the files from the source tree; they are
not bundled resources.

Notifications after the initial listing carry only the attributes that
changed.
