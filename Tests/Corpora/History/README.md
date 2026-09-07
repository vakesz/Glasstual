# Historical history fixture

`v1.0.7-history.sqlite` is synthetic data encoded in the shipped v1.0.7 format.
It is not a customer database and does not claim coverage of every historic OS
or damaged store. Its schema is copied verbatim from tag `v1.0.7`, commit
`6ade81a8e9b6040728963d29541c4b51477c5172`, at:

`Sources/App/Features/ChannelView/History/HistoricLogFileStorageModel.xcdatamodeld/LogControllerStorageModel (model 3).xcdatamodel/contents`

The frozen encoder in `GenerateFixture.swift` follows `LogLineArchive.encode`
and `LogLine.historicEntry` from that same revision, including the `TVCLogLine`
runtime root, secure keyed-archive envelope, field names and raw enum values.
It never imports the current application encoder. Copyright and license terms
are retained in `LICENSE.txt`.

The five rows deliberately include gapped insertion IDs and three rows sharing
the insertion ID, timestamp and line identifier, with different archive bodies.
Core Data writes its normal metadata and permanent object IDs when the fixture
is generated. Tests copy this checked-in file to temporary storage, never modify
the original, and compare all original blobs and identifiers after reopen and
append. They also page through every physical row and test retention separately.

Regenerate offline on macOS, without building the app:

```sh
xcrun momc Tests/Corpora/History/v1.0.7-model3.xcdatamodel /tmp/v1.0.7-model3.mom
xcrun swiftc -parse-as-library Tests/Corpora/History/GenerateFixture.swift -o /tmp/generate-history-fixture
/tmp/generate-history-fixture /tmp/v1.0.7-model3.mom /tmp/v1.0.7-history.sqlite
```

The generator refuses to replace an existing destination. Review and replace
the binary fixture deliberately, not as a test or build phase.
