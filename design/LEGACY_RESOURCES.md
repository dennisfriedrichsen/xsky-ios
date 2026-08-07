# Legacy resource provenance

`Resources/LegacyCatalogs` contains byte-for-byte copies from the sibling
legacy XSky repository. They were copied from legacy commit
`1260cfcb8c59f3c9f79427ec2e8264ecf40d83c8`.

## Runtime and parser resources

| File | Bytes | SHA-256 |
|---|---:|---|
| `ybs.dat` | 1,188,451 | `ae07e42366d7cf5feaacef17c150459dd17970f6a7cd0d3a5a569e7451380326` |
| `rngc.dat` | 281,700 | `bb7ca9c6f83442e7263a2565e4a9e9d8318ed3d626f3f87969f3483ad3168d26` |
| `qso.dat` | 71,906 | `dc6d954ff57492bab8f1e4e9f48987ac1dee7ca245a0c90900dab788d20de78e` |
| `boundaries.dat` | 300,081 | `6e5b91f84988a37cc4fa5464cef11e97df76ff36eb57ceb17c5080e0f2c452aa` |
| `outlines.dat` | 21,367 | `05d73dd98a0f38b61fd704b7cc117d618d80f359b611b8614c6f2ebf2b580e89` |
| `concenters.dat` | 2,047 | `da4df5a6318a4dfc0e02590996270317eafa72007851352ac7b3203ea5c7a685` |
| `starnames.dat` | 9,128 | `bb8bb8cfc18dfedd63e9657c83ddc5e4e9e69bc3d795d4777cd13dcac65cde36` |
| `ngc_names.dat` | 2,088 | `1ceb31711d600b6442e12d2f54c129f988fe7c879e8c88a1664a873feaeef27c` |
| `rngc_desc.tab` | 5,657 | `2852f163c9d3cd14c1423f409a1e228b34f54129672bb263b66490afa8c3d589` |
| `rngc_ambig.dat` | 10 | `4df604f4d2a54550c92ddf830405a7f2b572bd85cb8dbac97aea1df4b0d0f7fe` |
| `ngc_desc.tab` | 9,042 | `b934e3e830ba03faba3c7d3f48e689f4ba7c1ad002c65448cd71a644d8f4223c` |
| `ngc_l_amb.dat` | 141 | `9f097dd54611c0541732b4677a24680bce9ae10c25f67ac7c11b2779d6e98b10` |
| `ngc_s_amb.dat` | 1,712 | `9a0a6cdfe26bfa54ae5102f4ab87ce7cbdaad059dfcde9767ac33e1113f72c48` |
| `usercat.example` | 339 | `930b1012c5804e817d9be00b1e565ad5476b291b9e26aced0fb398090388e845` |

The `ngc_*` description and ambiguity tables are included even though the
first milestone uses RNGC. They are small, are part of the legacy parser
support set, and keep a later NGC 2000 parser from requiring another data
migration. `usercat.example` is a required import and UI-test fixture.

## Documentation and notices

The same directory also contains `catalogs.doc`, `usercat.doc`,
`ACKNOWLEDGEMENTS`, `Copyright.txt`, and `Warranty.txt`. Keep the original
notices intact. A human must review the redistribution terms before an App
Store or commercial release; this document makes no legal conclusion.

## Binary cache policy

No legacy `.bin` files were present or copied. XSky's optional binary catalogs
were native C structure dumps whose byte order, alignment, field sizes, and
ABI are not portable to iOS. Parse the text resources off the main actor. If
startup measurements later justify a derived cache, define a versioned,
portable schema with source SHA-256 and parser-version invalidation; never
commit or distribute a native memory dump.
