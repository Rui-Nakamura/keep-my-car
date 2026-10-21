External ZIP Backup v1 fixtures

`zip_v1_plan.json` is a hand-written external contract, independent of app
serialization. It includes funding OFF with retained amounts, negative/zero IDs,
same-month list order, null memo, year 0000, and reserve age above ownership age.

`generate_zip_v1.ps1` uses .NET System.IO.Compression and SHA256 to generate
`zip_v1_stored.zip` and `zip_v1_deflate.zip`. Neither archive nor the app codecs
participate in generation. Run `pwsh -File test/backup/fixtures/generate_zip_v1.ps1`
from the repository root to regenerate them; JSON raw byte changes require
regeneration because hashes deliberately cover the original bytes.
