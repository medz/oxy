Map<String, String> parseHeaderParams(String? header) {
  final result = <String, String>{};
  if (header == null || header.isEmpty) return result;

  for (final part in header.split(';')) {
    final [name, ...values] = part.split('=');
    final normalizedName = name.toLowerCase().trim();
    if (normalizedName.isEmpty) continue;

    String value = values.join('=').trim();
    if (value.startsWith("'") || value.startsWith('"')) {
      value = value.substring(1);
    }
    if (value.endsWith("'") || value.endsWith('"')) {
      value = value.substring(0, value.length - 1);
    }

    result[normalizedName] = value;
  }

  return result;
}
