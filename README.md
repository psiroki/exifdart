# exifdart

Dart module to decode Exif data from jpeg files.

Dart port based on Exif.js:
<https://github.com/exif-js/exif-js/>

## Installation

### Depend on it
Add this to your package's pubspec.yaml file:

```YAML
dependencies:
  exifdart:
```

### Install it
You can install packages from the command line:
```
$ pub get
```

## Usage

Simple example:
```Dart
// Add this to have the Rational class too:
// import "package:package:exifdart/exifdart.dart";

// We are not using that in this example, this alone will do fine:
import "package:package:exifdart/exifdart_html.dart";
import "dart:html";

/// Returns the orientation value or `null` if no EXIF or no orientation info
/// is found.
Future<int> getOrientation(Blob blob) async {
  if (blob.type == "image/jpeg") {
    Map<String, dynamic> tags = await readExifFromBlob(blob);
    return tags["Orientation"];
  }

  return null;
}

void main() {
  registerChangeHandler(document.querySelector("input[type=file]"));
}

void registerChangeHandler(InputElement input) {
  input.onChange.listen((Event e) {
    for (File f in input.files) {
      getOrientation(f).then((int orientation) {
        window.console.log("Orientation for ${f.name} is ${orientation}");
      });
    }
  });
}
```
