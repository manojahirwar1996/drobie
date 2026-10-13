import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { presign, presignR2, userObjectKey } from "./r2.ts";
import { setEnv } from "./testing.ts";

Deno.test("SigV4 presign matches the AWS documented test vector", async () => {
  // https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-query-string-auth.html
  const url = await presign({
    method: "GET",
    host: "examplebucket.s3.amazonaws.com",
    path: "/test.txt",
    accessKeyId: "AKIAIOSFODNN7EXAMPLE",
    secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    region: "us-east-1",
    expiresSeconds: 86400,
    now: new Date("2013-05-24T00:00:00Z"),
  });
  assertEquals(
    new URL(url).searchParams.get("X-Amz-Signature"),
    "aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404",
  );
});

const U = "0192a3b4-c5d6-7e8f-9a0b-1c2d3e4f5a6b";
const M = "0192a3b4-c5d6-7e8f-9a0b-aaaaaaaaaaaa";

Deno.test("object keys are always under the owner's prefix and contain no names", () => {
  assertEquals(userObjectKey(U, "item_photo", M, "master", "webp"), `u/${U}/item_photo/${M}/master.webp`);
  assertThrows(() => userObjectKey(U, "item_photo", "../../etc", "master", "webp"));
  assertThrows(() => userObjectKey(U, "Item Photo", M, "master", "webp"));
});

Deno.test("presignR2 refuses keys owned by someone else", async () => {
  const restore = setEnv({
    R2_ACCOUNT_ID: "acct",
    R2_BUCKET: "drobie-media",
    R2_ACCESS_KEY_ID: "k",
    R2_SECRET_ACCESS_KEY: "s",
  });
  try {
    const other = "0192a3b4-c5d6-7e8f-9a0b-bbbbbbbbbbbb";
    await assertRejects(() => presignR2("GET", other, `u/${U}/item_photo/${M}/thumb.webp`, 3600));
    const url = new URL(await presignR2("PUT", U, `u/${U}/item_photo/${M}/master.webp`, 300, "image/webp"));
    assertEquals(url.host, "acct.r2.cloudflarestorage.com");
    assertEquals(url.searchParams.get("X-Amz-Expires"), "300");
    assertEquals(url.searchParams.get("X-Amz-SignedHeaders"), "content-type;host");
  } finally {
    restore();
  }
});
