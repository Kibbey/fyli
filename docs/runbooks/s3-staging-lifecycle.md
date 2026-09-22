# Runbook: S3 staging lifecycle rule

**Bucket:** `cimplur`
**Applies to:** the `staging/` and `test/staging/` prefixes only
**Introduced by:** instant uploads (`docs/tdd/instant-uploads.md`)

## What this is for

Media now uploads while the parent is typing, into a user-scoped staging prefix
keyed by an opaque token. At save the memory is created and the staged tokens
are *claimed* — the image rendition is copied to its final key and the video is
read in place by MediaConvert.

A parent who picks files and then closes the tab leaves staged objects behind.
There is no cleanup job and no delete call anywhere in the application: the
lifecycle rule is the whole cleanup story. `removeFile` in the client makes no
network request at all, which is what keeps abandonment free of edge cases.

## Why the bucket is not in CloudFormation

`fyli-infra` is CloudFormation for the cluster and VPC; the `cimplur` bucket is
not managed there. So this rule is applied with the CLI and captured here.

## The rule

48 hours per the product decision, expressed as `Days: 2` — S3 expiration
granularity is daily and rounds up, so an object always gets at least 48 hours
from creation.

```json
{
  "Rules": [
    {
      "ID": "ExpireUnclaimedStagingObjects",
      "Status": "Enabled",
      "Filter": { "Prefix": "staging/" },
      "Expiration": { "Days": 2 },
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 1 }
    },
    {
      "ID": "ExpireUnclaimedStagingObjectsNonProd",
      "Status": "Enabled",
      "Filter": { "Prefix": "test/staging/" },
      "Expiration": { "Days": 2 },
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 1 }
    }
  ]
}
```

Both prefixes are needed: `S3StagedStorage.KeyFor` mirrors
`ImageService.GetName`'s `Constants.InProduction` convention and writes
`test/staging/…` outside production.

## Applying it

`put-bucket-lifecycle-configuration` **replaces** the entire configuration for
the bucket. Read the current one first and merge, or any existing rule is
silently dropped.

```bash
# 1. Capture what is there now.
aws s3api get-bucket-lifecycle-configuration --bucket cimplur \
  > /tmp/cimplur-lifecycle-before.json

# 2. Merge the two rules above into it, then apply.
aws s3api put-bucket-lifecycle-configuration \
  --bucket cimplur \
  --lifecycle-configuration file://staging-lifecycle.json

# 3. Verify.
aws s3api get-bucket-lifecycle-configuration --bucket cimplur
```

## Critical: never widen the prefix

Claimed media lives at `{userId}/{dropId}/{imageId}` and
`{userId}/{dropId}/m/{movieId}`. Those keys must never be reaped.

The design makes this safe by construction: claim **copies out of** staging
rather than moving within it, so no object a memory depends on ever lives under
the `staging/` prefix. A rule whose prefix was broadened — to `""`, or to a
`{userId}/` prefix — would delete parents' photos.

Video is the one case where a claimed memory still depends on a staging object
*after* the claim: MediaConvert reads it. Transcodes start within seconds and
finish in minutes, so 48 hours is three orders of magnitude of headroom. The
claim also refuses a staged upload whose `UploadedAt` is more than 24 hours old,
returning a per-token `"expired"` failure rather than copying from a key the
rule may already have deleted.

## Checking it is working

Unclaimed rows older than the lifecycle window should be zero. The filtered
`IX_StagedUploads_Unclaimed` index serves this directly:

```sql
SELECT COUNT(*)
FROM [StagedUploads]
WHERE [ClaimedDropId] IS NULL
  AND [CreatedAt] < DATEADD(hour, -72, SYSUTCDATETIME());
```

A non-zero count is expected and harmless — the SQL rows are ~200 bytes each and
are not pruned; only the S3 objects are. It becomes interesting only if it grows
without bound, which would suggest the staging flow is failing for real users.
Confirm the objects themselves are gone:

```bash
aws s3 ls s3://cimplur/staging/ --recursive --summarize | tail -3
```
