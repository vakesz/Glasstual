# Scrollback row fixture

`ScrollbackPayload-v1.plist` is one stored scrollback row in the only format
Glasstual has: `ChatLineStoredPayload` version 1, the property list
`ChatLine.scrollbackEntry(forView:)` writes into the `lineData` column of the
`ScrollbackEntry` entity. It is synthetic — no customer data — and every field a
line can carry is set to something distinguishable, including both optional
message identifiers, both keyword lists and a reaction.

`ChatLineTests` reads it two ways, and both matter:

- it decodes into a `ChatLine` and every field is checked, so a change to the
  encoder that drops or re-types a field fails here;
- the line is re-encoded and the field names of the result are compared with the
  field names in this file, so renaming a `ChatLine` property without updating
  `ChatLine.CodingKeys` fails here instead of silently invalidating every row on
  a user's disk.

This is the only format there is. Glasstual reads no other scrollback layout
and mints a fresh database when it cannot open one (see
`Sources/App/Chat/History/Scrollback/`), so no other fixture is kept.

Edit this file by hand, in step with `ChatLine.CodingKeys`. It is loaded from the
source tree through `#filePath`, not as a bundled test resource, so it is not in
`project.yml`.
