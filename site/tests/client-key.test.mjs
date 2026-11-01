import test from "node:test";
import assert from "node:assert/strict";
import { clientKey } from "../lib/client-key.ts";

test("IPv6 clients share one key per /64 and IPv4 stays exact", () => {
  assert.equal(clientKey("2001:db8:1:2:aaaa::1"), clientKey("2001:db8:1:2:bbbb:cccc:dddd:eeee"));
  assert.equal(clientKey("2001:0DB8:0001:0002::1"), clientKey("2001:db8:1:2:ffff::"));
  assert.notEqual(clientKey("2001:db8:1:2::1"), clientKey("2001:db8:1:3::1"));
  assert.equal(clientKey("2001:db8::1"), "2001:db8:0:0::/64");
  assert.equal(clientKey("fe80::1%en0"), clientKey("fe80::2"));
  assert.equal(clientKey("::1"), "0:0:0:0::/64");
  assert.equal(clientKey("::ffff:203.0.113.7"), "203.0.113.7");
  assert.equal(clientKey("203.0.113.7"), "203.0.113.7");
  assert.equal(clientKey(null), "direct");
  assert.equal(clientKey(""), "direct");
});
