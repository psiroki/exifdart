# 0.8.0-dev.2

- Fixed most warnings and hints
- However I'm not going to lie down to the quote mafia, I'm pretty sure
  the velociraptors aren't coming (https://xkcd.com/292/)
- I'm not going to remove local variable types from the ported JS code,
  because I think it's dumb, and dangerous, but I did remove local
  variable types for trivial cases to make somebody somewhere less
  unhappy about my package
- Don't get me started on the lack of consistency of the two rules above

# 0.8.0-dev.1

- Dart 2.12
- Null safety

# 0.7.0+2

- added documentation
- added example

# 0.7.0+1

- fixed when FlashpixVersion is already a string

# 0.7.0

- ported to Dart 2

# 0.6.0+1

- fixed the botched release

# 0.6.0

- created `AbstractBlobReader` making the core implementation platform independent
- moved platform dependent code (a HTML Blob based implementation of `AbstractBlobReader`)
  available by importing `exifdart_html.dart`
- created a `dart:io` based implementation of `AbstractBlobReader` and made it available
  in `exifdart_io.dart`
- this is an API breaking release, you have to import both `exifdart.dart` and
  `exifdart_html.dart` ot get the old API

# 0.5.0+6

- fixed `null` access on some files that have a type 0 GPSVersionID tag

# 0.5.0+5

- fixed offset errors in `BlobView` and `CacheView`

# 0.5.0+4

- changed switch block to make dart2js happy
