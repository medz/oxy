const headers = new Headers();
headers.append("name", "value");
headers.append("Name", "value 2");

console.log(Array.from(headers.entries()));

new Request();
new ReadableStreamDefaultReader();
