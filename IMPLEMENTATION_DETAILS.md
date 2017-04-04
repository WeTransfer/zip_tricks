# Implementation details

The ZipTricks streaming implementation is designed around the following requirements:

* Only ahead-writes (no IO seek or rewind)
* Automatic switching to Zip64 as the files get written (no IO seeks), but not requiring Zip64 support if the archive can do without
* Make use of the fact that CRC32 checksums and the sizes of the files (compressed _and_ uncompressed) are known upfront

It strives to be compatible with the following unzip programs _at the minimum:_

* OSX - builtin ArchiveUtility (except the Zip64 support when files larger than 4GB are in the archive)
* OSX - The Unarchiver, at least 3.10.1
* Windows 7 - built-in Explorer zip browser (except for Unicode filenames which it just doesn't support)
* Windows 7 - 7Zip 9.20

Below is the list of _specific_ decisions taken when writing the implementation, with an explanation for each.
We specifically _omit_ a number of things that we could do, but that are not necessary to satisfy our objectives.
The omissions are _intentional_ since we do not want to have things of which we _assume_ they work, or have things
that work only for one obscure unarchiver in one obscure case (like WinRAR with chinese filenames).

## Data descriptors (postfix CRC32/file sizes)

Data descriptors permit you to generate "postfix" ZIP files (where you write the local file header without having to
know the CRC32 and the file size upfront, then write the compressed file data, and only then - once you know what your CRC32,
compressed and uncompressed sizes are etc. - write them into a data descriptor that follows the file data.

The streamer has optional support for data descriptors. Their use can apparently [ be problematic](https://github.com/thejoshwolfe/yazl/issues/13)
with the 7Zip version that we want to support, but in our tests everything worked fine.

For more info see https://github.com/thejoshwolfe/yazl#general-purpose-bit-flag

## Zip64 support

Zip64 support switches on _by itself_, automatically, when _any_ of the following conditions is met:

* The start of the central directory lies beyound the 4GB limit
* The ZIP archive has more than 65535 files added to it
* Any entry is present whose compressed _or_ uncompressed size is above 4GB

When writing out local file headers, the Zip64 extra field (and related changes to the standard fields) are
_only_ performed if one of the file sizes is larger than 4GB. Otherwise the Zip64 extra will _only_ be
written in the central directory entry, but not in the local file header.

This has to do with the fact that otherwise we would write Zip64 extra fields for all local file headers,
regardless whether the file actually requires Zip64 or not. That might impede some older tools from reading
the archive, which is a problem you don't want to have if your archive otherwise fits perfectly below all
the Zip64 thresholds.

To be compatible with Windows7 built-in tools, the Zip64 extra field _must_ be written as _the first_ extra
field, any other extra fields should come after.

## International filename support and the Info-ZIP extra field

If a diacritic-containing character (such as å) does fit into the DOS-437
codepage, it should be encodable as such. This would, in theory, let older Windows tools
decode the filename correctly. However, this kills the filename decoding for the OSX builtin
archive utility (it assumes the filename to be UTF-8, regardless). So if we allow filenames
to be encoded in DOS-437, we _potentially_ have support in Windows but we upset everyone on Mac.
If we just use UTF-8 and set the right EFS bit in general purpose flags, we upset Windows users
because most of the Windows unarchive tools (at least the builtin ones) do not give a flying eff
about the EFS support bit being set.

Additionally, if we use Unarchiver on OSX (which is our recommended unpacker for large files),
it will (very rightfully) ask us how we should decode each filename that does not have the EFS bit,
but does contain something non-ASCII-decodable. This is horrible UX for users.

So, basically, we have 2 choices, for filenames containing diacritics (for bona-fide UTF-8 you do not
even get those choices, you _have_ to use UTF-8):

* Make life easier for Windows users by setting stuff to DOS, not care about the standard _and_ make
  most of Mac users upset
* Make life easy for Mac users and conform to the standard, and tell Windows users to get a _decent_
  ZIP unarchiving tool.

We are going with option 2, and this is well-thought-out. Trust me. If you want the crazytown
filename encoding scheme that is described here http://stackoverflow.com/questions/13261347
you can try this:

   [Encoding::CP437, Encoding::ISO_8859_1, Encoding::UTF_8]

We don't want no such thing, and sorry Windows users, you are going to need a decent unarchiver
that honors the standard. Alas, alas.

Additionally, the tests with the unarchivers we _do_ support have shown that including the InfoZIP
extra field does not actually help any of them recognize the file name correctly. And the use of
those fields for the UTF-8 filename, per spec, tells us we should not set the EFS bit - which ruins
the unarchiving for all other solutions. As any other, this decision may be changed in the future.

There are some interesting notes about the Info-ZIP/EFS combination here
https://commons.apache.org/proper/commons-compress/zip.html

## Directory support

ZIP offers the possibility to store empty directories (folders). The directories that contain files, however, get
created automatically at unarchive time.  If you store a file, called, say, `docs/item.doc` then the unarchiver will
automatically create the `docs` directory if it doesn't exist already. So you need to use the directory creation
methods only if you do not have any files in those directories.