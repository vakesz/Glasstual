# Changelog

Notable changes to Glasstual. The GitHub release notes are generated from the
commits of each release; this file carries the lines those notes should not
lose, above all the changes a user notices without reading a commit.

## Unreleased

### Changed

- Autojoin sends every channel at once, in as many `JOIN` lines as the server
  allows, and lets the connection's flood control pace them. The two settings
  that throttled it — the delay between joins and the number of channels per
  join — are gone; a stored value for either is ignored.
- The nine `TextField…` input settings (smart quotes, dashes, text replacement,
  spelling and grammar checks, and their siblings) now travel in exported
  configuration files. Importing a file written by an earlier version is
  unaffected, since those keys were simply absent.
- Search moved from the top of the sidebar to the window toolbar.
- Replayed lines that arrive in the ten seconds after joining a channel no
  longer mark it unread, raise a highlight badge or post a notification. The
  server's read marker decides what is unread afterwards.
- Flood-control values on rate-limited networks are written to the connection
  list explicitly, so a reduced burst limit survives a save and reload.
- Stored scrollback is stamped with the line's own time rather than the moment
  it was written, so replayed history sorts where it was said. Rows written by
  earlier versions are re-stamped once, the first time the store opens.

### Added

- Settings › IRCv3 lists every automatically negotiated capability with a
  short description, a link to its specification and a switch to turn it off.
- Server Properties › Connect Commands can hold the channel joins until a
  chosen number of seconds after the connect commands have been sent.
- Server Properties, Channel Properties and the Settings window can be resized.

### Fixed

- The TLS lock indicator never appeared, because the secured state was
  checked before the handshake had run.
- Clearing a server, NickServ or proxy password did not remove it from the
  keychain; the old password came back on the next connection.
- A DCC resume could append into an unrelated file of the same name in the
  download folder.
- Opening a channel now clears its badge immediately and scrolls the
  transcript to the newest line.
- Loading older scrollback no longer discards the newest lines from the view.
- Context menus showed items that should have been hidden, such as both
  Connect and Disconnect on a connected server.
- A quit confirmation could be shown twice and run the shutdown twice.
