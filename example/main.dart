import 'package:oxy/oxy.dart';

Future<void> main() async {
  final form = FormData();
  form.append("key", FormDataEntry.text("Value"));
  form.append("File", FormDataEntry.file(Stream.empty()));

  final res = await oxy(
    Request(
      "https://webhook.site/3d677b67-b4ea-4c3b-9066-b439bd8579e3",
      method: "POST",
      body: Body.formData(form),
    ),
  );

  print(await res.text());
}
