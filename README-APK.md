# NilamChat — GitHub APK Build

This repository contains the NilamChat web app wrapped with Capacitor. GitHub Actions creates the Android project and builds the APK automatically, so the generated `android/` folder does not need to be committed.

## GitHub upload

1. Create a new GitHub repository.
2. Upload all files from this folder to the repository root.
3. Commit to the `main` branch.
4. Open **Actions** → **Build NilamChat APK**.
5. Run the workflow with **Run workflow** if it did not start automatically.
6. When it finishes, open the workflow run and download the **NilamChat-APK** artifact.

## Supabase

Before using the app, put the Supabase Project URL and anon/publishable key in `config.js`, or enter them on the app's connection screen. Never use a Supabase service-role key in the frontend.

## Local build

```bash
npm install
npm run build
npx cap add android
npx cap sync android
cd android
./gradlew assembleRelease
```

The APK will be at:
`android/app/build/outputs/apk/release/app-release-unsigned.apk`

## APK installation fix
The GitHub Actions workflow builds `assembleDebug` instead of the unsigned release APK. The resulting `NilamChat.apk` is automatically debug-signed by Gradle and is directly installable on Android.
