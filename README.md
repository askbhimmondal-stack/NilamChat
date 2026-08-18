<img src="https://i.ibb.co/23GZsVxm/Screenshot-2026-08-17-104134.png" alt="Screenshot 2026 08 17 104134" border="0">

A mobile-friendly real-time 1-to-1 chat website based on the NilamChat Flutter project.

## Features
- Email/password authentication
- Register/login/forgot password
- Real-time 1-to-1 text chat using Supabase Realtime
- Search users and start conversations
- Online/offline profile status
- Unread counts and read receipts via existing Supabase RPCs
- Profile and settings drawer
- Responsive mobile layout
- No build step required; deploy directly to Netlify

## 1. Supabase
Use the same Supabase project as the Flutter app.

Run:
1. `supabase/schema.sql`
2. `supabase/policies.sql`
3. Create Storage bucket `chat-media` and make it public if you want media support later.
4. Enable Email authentication.
5. Make sure `messages` and `profiles` are in `supabase_realtime`.

Important: if your old schema produced `last_message_at specified more than once`, use the corrected view definition from the Flutter project's fixed schema before using the web app.

## 2. Configure the website
Open `config.js` and set:

```js
window.NILAMCHAT_CONFIG = {
  supabaseUrl: "https://YOUR_PROJECT.supabase.co",
  supabaseAnonKey: "YOUR_ANON_OR_PUBLISHABLE_KEY"
};
```

Only use the public anon/publishable key. Never use the service-role key.

You can also leave them empty: when the site opens, it will show a setup screen where you can enter the values. Those values are stored in that browser's localStorage.

## 3. Netlify
### Drag & drop
1. Extract this ZIP.
2. Open Netlify.
3. Go to Sites / Add new site / Deploy manually.
4. Drag the `NilamChat-Web` folder into the deploy area.

### GitHub
Upload the contents of this folder to a GitHub repository and connect that repository to Netlify. Build command is empty. Publish directory is `.`.

## 4. Supabase Auth redirect
For forgot-password redirects, add your Netlify URL in Supabase:
Authentication → URL Configuration → Redirect URLs.

Example:
`https://your-site.netlify.app/**`

## Note
This web build intentionally uses the same Supabase tables/RPCs as the Flutter app, so Flutter and Web users can chat with each other through the same backend.

### Delete chat
Run the latest `schema.sql` in Supabase SQL Editor after updating the project. The app includes **Delete chat** in the contact menu (⋮) inside an open conversation. It removes the chat from the current user's chat list while keeping the other participant's copy.
