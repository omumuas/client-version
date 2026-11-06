import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { atLeast, clientVersionOf, compare, evaluate, parse } from "../src/index.ts";

const cases = JSON.parse(readFileSync(new URL("../cases.json", import.meta.url), "utf8"));

for (const c of cases.parse) {
  test(`parse ${JSON.stringify(c.input)}`, () => assert.deepEqual(parse(c.input), c.expected));
}
for (const c of cases.compare) {
  test(`compare ${c.a} ${c.b}`, () => {
    assert.equal(compare(c.a, c.b), c.expected);
    assert.equal(compare(c.b, c.a), -c.expected || 0);
  });
}
for (const c of cases.evaluate) {
  test(`evaluate: ${c.name}`, () => {
    const r = evaluate(c.policy, c.clientVersion, c.method);
    assert.equal(r.level, c.expected.level);
    assert.equal(r.refuse, c.expected.refuse);
    assert.deepEqual(r.headers, c.expected.headers);
    if (c.expected.refuse) assert.deepEqual(r.body, c.expected.body);
  });
}
for (const c of cases.atLeast) {
  test(`atLeast ${c.clientVersion} ${c.version}`, () => assert.equal(atLeast(parse(c.clientVersion), c.version), c.expected));
}

test("clientVersionOf: header wins over query parameter", () => {
  const both = new Request("https://x/api?client_version=a%2F1%20(web)", { headers: { "X-Client-Version": "b/2 (macos)" } });
  assert.equal(clientVersionOf(both), "b/2 (macos)");
  assert.equal(clientVersionOf(new Request("https://x/api?client_version=a%2F1%20(web)")), "a/1 (web)");
  assert.equal(clientVersionOf(new Request("https://x/api")), null);
});
