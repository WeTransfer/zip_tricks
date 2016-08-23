## The _actual_ testing for ZipTricks

Consists of a fairly straightforward procedure.

1. Run `generate_test_files.rb`. This will take some time and produce a number of ZIP files.
2. Open them with the following ZIP unarchivers:
  * A recent version of `zipinfo` with the `-tlhvz` flags - to see the information about the file
  * ArchiveUtility on OSX
  * The Unarchiver on OSX
  * Built-in Explorer on Windows 7
  * 7Zip 9.20 on Windows 7
* Write down your observations in `test-report.txt` and, when cutting a release, timestamp a copy of that file.
