## Manual testing harness for ZipTricks

These tests will generate **very large** files that test various edge cases of ZIP generation. The idea is to generate
these files and to then try to open them with the unarchiver applications we support. The workflow is as follows:


1. Configure your storage to have `zip_tricks` directory linked into your virtual machines and to be on a fast volume (SSD RAID0 is recommended)
2. Run `generate_test_files.rb`. This will take some time and produce a number of large ZIP files.
3. Open them with the following ZIP unarchivers:
  * A recent version of `zipinfo` with the `-tlhvz` flags - to see the information about the file
  * ArchiveUtility on OSX
  * The Unarchiver on OSX
  * Built-in Explorer on Windows 7
  * 7Zip 9.20 on Windows 7
  * Any other unarchivers you consider necessary
* Write down your observations in `test-report.txt` and, when cutting a release, timestamp a copy of that file.
