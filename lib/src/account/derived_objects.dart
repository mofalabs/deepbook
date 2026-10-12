/// Derivation of `0x2::derived_object` ids, package-internal.
///
/// Mirrors `deriveObjectID` from the official `@mysten/sui/utils`: a derived
/// object's id is the dynamic-field id of the parent under a
/// `DerivedObjectKey<T>` wrapper tag. The TypeScript SDK ships this helper in
/// the sui package; the Dart sui package only ships [deriveDynamicFieldID],
/// so the wrapper lives here until it does.
library;

import 'dart:typed_data';

import 'package:sui/utils/dynamic_fields.dart' show deriveDynamicFieldID;

/// The id of an object created through `0x2::derived_object::claim` on
/// [parentId] with key type [typeTag] and BCS-encoded key value [key].
String deriveObjectID(String parentId, String typeTag, Uint8List key) =>
    deriveDynamicFieldID(
      parentId,
      '0x2::derived_object::DerivedObjectKey<$typeTag>',
      key,
    );
