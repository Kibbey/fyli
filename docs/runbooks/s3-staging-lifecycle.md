# Runbook: the staging bucket and its expiration rule

**Bucket:** `cimplur-staging` (us-east-1)
**Introduced by:** instant uploads (`docs/tdd/archive/instant-uploads.md`)

## What this is for

Media now uploads while the parent is typing, into a staging bucket keyed by an
opaque token. At save the memory is created and the staged tokens are *claimed*
— the image rendition is copied into `cimplur` and the video is read in place by
MediaConvert.

A parent who picks files and then closes the tab leaves staged objects behind.
There is no cleanup job and no delete call anywhere in the application: the
expiration rule is the whole cleanup story. `removeFile` in the client makes no
network request at all, which is what keeps abandonment free of edge cases.

## Why a separate bucket

Everything in `cimplur-staging` is disposable, so its expiration rule carries
**no prefix filter at all**. That is the point of the separate bucket: there is
no prefix to mistype and none to widen later, and nothing here that a memory
depends on.

The earlier design put staging under a `staging/` prefix inside `cimplur`, the
media bucket. That was safe — `userId` is an int, so live keys always start with
a digit and can never match `staging/` — but it made a *deletion* rule on the
bucket holding every memory photo, and its safety depended on every future
editor understanding that the prefix was load-bearing. A dedicated bucket makes
"everything here expires" a property of the bucket instead of a rule someone has
to remember. `cimplurthumbs` is the existing precedent for a purpose-specific
bucket.

`StagedClaimHandlerTest.VideoClaim_InputAndOutputAreInDifferentBuckets` and
`StagedStorage_StagingAndMediaBucketsAreDistinct` fail if the two are ever
collapsed back together.

## Configuration

All of this is applied; recorded here so it can be rebuilt or audited.

```bash
aws s3api create-bucket --bucket cimplur-staging --region us-east-1

aws s3api put-public-access-block --bucket cimplur-staging \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

**Expiration** — 2 days rather than a literal 48 hours: S3 evaluates
expirations once a day at UTC midnight, so `Days: 2` guarantees *at least* 48h
and in practice means 48–72h. The claim path independently refuses anything
whose `UploadedAt` is over 24h old, so nothing depends on the rule's precise
timing.

```json
{
  "Rules": [
    {
      "ID": "ExpireStagedUploads",
      "Status": "Enabled",
      "Filter": {},
      "Expiration": { "Days": 2 },
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 1 }
    }
  ]
}
```

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket cimplur-staging --lifecycle-configuration file://staging-lifecycle.json
```

**CORS** — required for the video presigned `PUT`, which goes direct from the
browser to S3. Images never need it; they post to the API. Origins mirror the
`cimplur` bucket's rule, minus `POST`, which staging does not use.

```json
{
  "CORSRules": [
    {
      "AllowedHeaders": ["*"],
      "AllowedMethods": ["PUT"],
      "AllowedOrigins": [
        "https://app.fyli.com",
        "https://app.cimplur.com",
        "http://localhost:8000",
        "http://localhost:5174"
      ],
      "ExposeHeaders": ["ETag"],
      "MaxAgeSeconds": 3000
    }
  ]
}
```

## Access

Granted by a **bucket policy on `cimplur-staging`**, not by editing IAM roles.
For S3 within one account, identity and resource policies union, so this works
whatever `fyli-task-role`'s inline policy says — which matters, because that
policy is not readable with the deploy user's credentials
(`iam:ListRolePolicies` is denied) and may well be scoped to
`arn:aws:s3:::cimplur/*`.

| Principal | Granted | Why |
|---|---|---|
| `fyli-task-role` | `PutObject`, `GetObject`, `DeleteObject` on `cimplur-staging/*`; `ListBucket`, `GetBucketLocation` on the bucket | Writes image renditions, presigns video PUTs, reads sizes, and is the signer whose permissions a presigned URL carries |
| `MediaConvert_Default` | `GetObject` on `cimplur-staging/*` | Reads the staged original. Redundant — the role already has `AmazonS3FullAccess` — but stated so the bucket documents its own readers |

The claim copy also needs `s3:PutObject` on `cimplur/*`, which the task role
already has: it writes drop images there today.

**The one thing a bucket policy cannot override is an explicit `Deny`.** If
`fyli-task-role`'s inline policy explicitly denies S3 outside `cimplur`, this
grant is ineffective and staging fails closed — every stage request errors, the
client falls back to the legacy per-drop upload path, and the parent loses the
speed improvement but nothing else. No data loss, no broken memories. Verified
after deploy by staging a real photo; see below.

Public access is blocked on all four settings. A bucket policy naming explicit
principals is not public, so `BlockPublicPolicy` does not reject it.

## Checking it is working

Unclaimed rows older than the window should trend to zero objects (the SQL rows
are not pruned, only the S3 objects):

```sql
SELECT COUNT(*)
FROM [StagedUploads]
WHERE [ClaimedDropId] IS NULL
  AND [CreatedAt] < DATEADD(hour, -72, SYSUTCDATETIME());
```

```bash
# Objects older than the window should not exist.
aws s3 ls s3://cimplur-staging/ --recursive --summarize | tail -3
```

A non-zero SQL count is expected and harmless — rows are ~200 bytes and the
filtered `IX_StagedUploads_Unclaimed` index makes a prune trivial if it ever
matters. It becomes interesting only if it grows without bound, which would
suggest staging is failing for real users.
