# Scrollback row fixture

`ScrollbackPayload-v1.plist` contains a synthetic `ChatLineStoredPayload`
version 1. `ChatLine.scrollbackEntry(forView:)` stores this property list in
`ScrollbackEntry.lineData`.

`ChatLineTests` checks every decoded field and the re-encoded field names.
Keep the fixture consistent with `ChatLine.CodingKeys`. It includes optional
message identifiers, keyword lists and a reaction.

The tests load the fixture from the source tree through `#filePath`.
It is not a bundled resource.
