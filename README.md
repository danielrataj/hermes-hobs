# Hermes Bots

Flutter client (iOS, Android, macOS) for chatting with the bots of a Hermes Agent
dashboard (default `https://hermes.devrel.cz`). In Hermes, each **profile** is a bot.

## Run

```bash
flutter pub get
flutter run -d macos   # or an iOS simulator / Android device
```

Sign in with the dashboard's username and password (provider `basic`).

## How it talks to Hermes

| Step | Call |
|---|---|
| Login | `POST /auth/password-login` `{provider:"basic",username,password}` → session cookies (`hermes_session_at/rt/provider`). The app stores them and saves every rotated `Set-Cookie`. |
| Bot list | `GET /api/profiles` |
| Chat socket | `POST /api/auth/ws-ticket` (single-use, 30 s) → `wss://…/api/ws?ticket=…`. JSON-RPC 2.0, one object per frame. No `Origin` header is sent. |
| Handshake | the server sends `event gateway.ready`, the client sends `client.capabilities {server_requests:true}`, and the client sends `gateway.ping` every 15 s |
| Conversation | `session.create {profile}` → `prompt.submit {session_id,text}` → events `message.start / message.delta / message.interim / tool.* / message.complete` |
| Control | `session.interrupt`, server requests `approval` (reply with `{choice}`) and `clarify` (reply with `{answers,outcome}`) |
| Reconnect | auto backoff, then `session.resume {session_id: stored_session_id}` |

Sessions (history) are intentionally out of scope: each bot gets one live
conversation per app run, and the "new conversation" button starts a fresh one.

## Layout

- `lib/api/hermes_http.dart`: cookie-aware REST client (dart:io)
- `lib/api/hermes_rpc.dart`: `/api/ws` JSON-RPC client (ticket, heartbeat, reconnect, server requests)
- `lib/state/chat_controller.dart`: one conversation, event → message model
- `lib/state/app_state.dart`: login, bot list, chats per bot
- `lib/ui/`: login, bot list (split view on wide screens), chat
- `test/`: fake Hermes server covering the whole flow

Web is not a target: browser CORS and cookie rules block cross-origin access to the dashboard.
