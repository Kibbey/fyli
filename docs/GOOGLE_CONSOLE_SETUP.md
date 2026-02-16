# Google Cloud Console Setup for Fyli Google Sign-In

## Overview

Fyli uses Google Identity Services (GIS) with the "Sign In With Google" button flow. The frontend loads Google's GIS client script, renders a button, and receives an ID token (JWT) on user consent. The backend verifies that ID token using the `Google.Apis.Auth` library against the configured Client ID.

This guide covers every setting required in the Google Cloud Console.

---

## 1. Create or Select a Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click the project dropdown at the top and select **New Project** (or use an existing one)
3. Name it (e.g. `fyli-prod`) and click **Create**
4. Select the project from the dropdown once created

---

## 2. Enable the Required API

1. Navigate to **APIs & Services > Library**
2. Search for **Google Identity Services** (or **Google Sign-In**)
3. No specific API needs to be explicitly enabled for basic Sign-In with Google button flow -- it works via the OAuth consent screen and credentials alone

---

## 3. Configure the OAuth Consent Screen

1. Navigate to **APIs & Services > OAuth consent screen**
2. Select **External** user type (allows any Google account to sign in)
3. Fill in the required fields:

| Field | Value |
|---|---|
| **App name** | `Fyli` |
| **User support email** | Your support email |
| **App logo** | Upload the Fyli logo (optional but recommended) |
| **App domain - Application home page** | `https://fyli.com` |
| **App domain - Privacy policy link** | `https://fyli.com/privacy` (or your actual URL) |
| **App domain - Terms of service link** | `https://fyli.com/terms` (or your actual URL) |
| **Authorized domains** | `fyli.com` |
| **Developer contact email** | Your email |

4. Click **Save and Continue**

### Scopes

1. Click **Add or Remove Scopes**
2. Add these scopes (these are the minimum needed):
   - `openid` -- basic authentication
   - `email` -- user's email address
   - `profile` -- user's name and profile picture
3. Click **Update**, then **Save and Continue**

### Test Users (only while in "Testing" status)

- While the consent screen is in **Testing** mode, only listed test users can sign in
- Add your test Google accounts here
- When ready for production, click **Publish App** to move to **In Production** status

---

## 4. Create OAuth 2.0 Client ID Credentials

1. Navigate to **APIs & Services > Credentials**
2. Click **+ Create Credentials > OAuth client ID**
3. Select **Web application** as the Application type
4. Name it (e.g. `Fyli Web Client`)

### Authorized JavaScript Origins

These are the domains from which the Google Sign-In button is loaded. Add all environments:

| Environment | Origin |
|---|---|
| **Local development** | `http://localhost:5174` |
| **Production** | `https://app.fyli.com` |

> Add any staging/preview URLs as well (e.g. `https://staging.fyli.com`).

### Authorized Redirect URIs

The GIS "Sign In With Google" button flow uses a **popup/callback** model -- it does NOT redirect the browser. However, Google still requires at least one redirect URI to be configured:

| Environment | Redirect URI |
|---|---|
| **Local development** | `http://localhost:5174` |
| **Production** | `https://app.fyli.com` |

> These are fallback entries. The actual token exchange happens client-side via the GIS JavaScript callback, not via server-side redirect.

5. Click **Create**
6. Copy the **Client ID** -- it looks like: `123456789-abcdefg.apps.googleusercontent.com`

---

## 5. Configure the Application

The Client ID must be set in **two places** -- the frontend and the backend. Both must use the **same Client ID**.

### Frontend (fyli-fe-v2)

Set the environment variable in `.env`:

```
VITE_GOOGLE_CLIENT_ID=123456789-abcdefg.apps.googleusercontent.com
```

This is read by `useGoogleSignIn.ts` at:
```typescript
const GOOGLE_CLIENT_ID = import.meta.env.VITE_GOOGLE_CLIENT_ID;
```

### Backend (cimplur-core)

Set `GoogleClientId` in `appsettings.json` (or via environment variable / secrets manager in production):

```json
{
  "GoogleClientId": "123456789-abcdefg.apps.googleusercontent.com"
}
```

This is read by `GoogleAuthService` via `AppSettings.GoogleClientId` and passed to `GoogleJsonWebSignature.ValidateAsync()` as the audience claim for token verification.

> **Critical:** The frontend Client ID and backend Client ID MUST match. If they differ, token verification will fail with `InvalidJwtException` (the audience claim won't match).

---

## 6. Production Checklist

Before going live:

- [ ] OAuth consent screen status is **In Production** (not Testing)
- [ ] `https://fyli.com` is in **Authorized JavaScript Origins**
- [ ] `https://fyli.com` is in **Authorized Redirect URIs**
- [ ] `fyli.com` is in **Authorized Domains** on the consent screen
- [ ] Frontend `.env` has `VITE_GOOGLE_CLIENT_ID` set to the production Client ID
- [ ] Backend `appsettings.json` (or env var) has `GoogleClientId` set to the same Client ID
- [ ] App name and logo on consent screen look correct (users see this during first sign-in)
- [ ] Privacy policy and terms of service URLs are valid and accessible

---

## 7. How It Works End-to-End

```
User clicks "Sign in with Google" button
        |
        v
Google GIS popup / inline consent screen
        |
        v
User authorizes --> Google returns ID token (JWT) to frontend callback
        |
        v
Frontend sends ID token to POST /api/users/google-auth
        |
        v
Backend calls GoogleJsonWebSignature.ValidateAsync(idToken, audience: ClientId)
        |
        v
Extracts email, name, Google subject ID from verified payload
        |
        v
Finds or creates user, links ExternalLogin record
        |
        v
Returns Fyli JWT --> Frontend stores in auth store
```

---

## 8. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Google button doesn't appear | `VITE_GOOGLE_CLIENT_ID` is empty | Set the env var and restart dev server |
| "Google Sign-In is not configured" error | Same as above | Set `VITE_GOOGLE_CLIENT_ID` in `.env` |
| Popup shows "Error 400: redirect_uri_mismatch" | Origin not in Authorized JavaScript Origins | Add the exact origin (including port) to Google Console |
| Backend returns "Invalid Google sign-in token" | Client ID mismatch between frontend and backend | Ensure both use the same Client ID |
| "Access blocked: app has not been verified" | Consent screen still in Testing mode | Either add user as test user or publish the app |
| Sign-in works locally but not in production | Production URL missing from Authorized Origins | Add `https://fyli.com` to both Origins and Redirect URIs |

---

## 9. Separate Credentials Per Environment (Recommended)

For better security, create **separate OAuth Client IDs** for each environment:

| Environment | Client ID Name | Origins |
|---|---|---|
| Development | `Fyli Dev` | `http://localhost:5174` |
| Production | `Fyli Prod` | `https://fyli.com` |

This prevents development tokens from being valid in production and vice versa. Each environment's `.env` and `appsettings.json` would reference its own Client ID.
