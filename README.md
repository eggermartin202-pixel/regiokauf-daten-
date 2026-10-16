# RegioKauf – Daten

Hier liegt die Liste der **freigegebenen heimischen Betriebe** für die RegioKauf-App.

- `betriebe.json` – wird automatisch gepflegt, nicht von Hand bearbeiten
- `fotos/` – Fotos der freigegebenen Betriebe
- `freigabe_bot.py` – holt deine ✅/❌-Klicks aus Telegram ab
- `.github/workflows/freigabe.yml` – startet den Bot alle 5 Minuten (kostenlos über GitHub Actions)

Die App liest: `https://raw.githubusercontent.com/eggermartin202-pixel/regiokauf-daten-/main/betriebe.json`

Benötigte Secrets (Settings → Secrets and variables → Actions):
`TELEGRAM_BOT_TOKEN`, `TELEGRAM_ADMIN_CHAT_ID`
