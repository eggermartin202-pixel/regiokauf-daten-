#!/usr/bin/env python3
"""
RegioKauf Freigabe-Bot
======================

Gegenstück zum TelegramBotHelper in der App. Läuft auf deinem PC (oder einem
kleinen Server) und wartet auf deine Button-Klicks in Telegram:

  ✅ Freigeben  -> Betrieb wird in betriebe.json eingetragen (und optional zu GitHub hochgeladen)
  ❌ Ablehnen   -> Nachricht wird als abgelehnt markiert, sonst passiert nichts

Die App lädt betriebe.json über die URL aus `betriebe.feedUrl` (local.properties).

Nur Python 3.9+ nötig, keine Zusatzpakete.

Umgebungsvariablen:
  TELEGRAM_BOT_TOKEN      Token von @BotFather (derselbe wie in der App)
  TELEGRAM_ADMIN_CHAT_ID  Deine Telegram-User-ID (nur deine Klicks zählen)
  GITHUB_TOKEN            optional: Fine-grained Token mit "Contents: Read and write"
  GITHUB_REPO             optional: z. B. "deinname/regiokauf-daten" (öffentliches Repo)
  GITHUB_PATH             optional: Pfad der Datei im Repo, Standard "betriebe.json"

  DATA_FILE               optional: wohin betriebe.json geschrieben wird

Start auf PC / Mini-PC (wartet dauerhaft, Freigabe in Sekunden):
    python freigabe_bot.py

Einmal-Modus für GitHub Actions (holt alle Klicks ab, verarbeitet sie, beendet sich):
    python freigabe_bot.py --once
"""

from __future__ import annotations

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
ADMIN_ID = os.environ.get("TELEGRAM_ADMIN_CHAT_ID", "")
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
GITHUB_REPO = os.environ.get("GITHUB_REPO", "")
GITHUB_PATH = os.environ.get("GITHUB_PATH", "betriebe.json")

DATA_FILE = Path(os.environ.get("DATA_FILE") or Path(__file__).with_name("betriebe.json"))
DATA_MARKER = "#DATEN"
REQUIRED = ("id", "name", "typ", "plz", "ort", "lat", "lon")


# --------------------------------------------------------------------------- Telegram

def tg_safe(method: str, **params) -> None:
    """Für Rückmeldungen an den Admin: ein Fehler (z. B. "query is too old" im
    Einmal-Modus) darf die eigentliche Freigabe nicht verhindern."""
    try:
        tg(method, **params)
    except Exception as e:  # noqa: BLE001
        print(f"Hinweis: {method} fehlgeschlagen: {e}", file=sys.stderr, flush=True)


def tg(method: str, **params) -> dict:
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{TOKEN}/{method}",
        data=json.dumps(params).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=70) as r:
        return json.load(r)


# --------------------------------------------------------------------------- Daten

def parse_betrieb(message_text: str) -> dict | None:
    """Liest den JSON-Block nach '#DATEN' aus der Bot-Nachricht."""
    if DATA_MARKER not in message_text:
        return None
    raw = message_text.split(DATA_MARKER, 1)[1].strip()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if not all(k in data for k in REQUIRED):
        return None
    return data


def load_list() -> list[dict]:
    if DATA_FILE.exists():
        return json.loads(DATA_FILE.read_text(encoding="utf-8"))
    return []


def upsert(entries: list[dict], betrieb: dict) -> list[dict]:
    return [e for e in entries if e.get("id") != betrieb["id"]] + [betrieb]


def save_list(entries: list[dict]) -> None:
    DATA_FILE.write_text(json.dumps(entries, ensure_ascii=False, indent=2), encoding="utf-8")


def github_put(path: str, content: bytes, message: str) -> None:
    """Legt eine Datei im (öffentlichen) GitHub-Repo an oder ersetzt sie."""
    url = f"https://api.github.com/repos/{GITHUB_REPO}/contents/{path}"
    headers = {"Authorization": f"Bearer {GITHUB_TOKEN}", "Accept": "application/vnd.github+json"}

    sha = None
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=20) as r:
            sha = json.load(r).get("sha")
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise

    body = {"message": message, "content": base64.b64encode(content).decode()}
    if sha:
        body["sha"] = sha
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers=headers, method="PUT")
    urllib.request.urlopen(req, timeout=30).close()


def push_to_github(entries: list[dict], fotos: list[str]) -> str:
    """Lädt Fotos und betriebe.json hoch, damit die App sie abrufen kann.
    Bei GitHub Actions nicht nötig: dort speichert der Workflow selbst (git commit)."""
    if not (GITHUB_TOKEN and GITHUB_REPO):
        return "gespeichert"
    folder = GITHUB_PATH.rpartition("/")[0]
    for rel in fotos:
        github_put(f"{folder}/{rel}" if folder else rel, (DATA_FILE.parent / rel).read_bytes(), "Foto hinzugefügt")
    github_put(GITHUB_PATH, json.dumps(entries, ensure_ascii=False, indent=2).encode(), "Betriebe-Liste aktualisiert")
    return "online veröffentlicht"


def download_fotos(betrieb: dict) -> list[str]:
    """Holt die Fotos (Telegram-Datei-IDs) und legt sie neben betriebe.json in fotos/.
    Liefert die Pfade relativ zu betriebe.json, so wie die App sie erwartet."""
    paths = []
    folder = DATA_FILE.parent / "fotos"
    for i, file_id in enumerate(betrieb.get("fotoIds", [])[:3], start=1):
        file_path = tg("getFile", file_id=file_id)["result"]["file_path"]
        with urllib.request.urlopen(f"https://api.telegram.org/file/bot{TOKEN}/{file_path}", timeout=60) as r:
            data = r.read()
        if not data.startswith(b"\xff\xd8"):  # nur echte JPEGs übernehmen
            continue
        folder.mkdir(parents=True, exist_ok=True)
        name = f"{betrieb['id']}-{i}.jpg"
        (folder / name).write_bytes(data)
        paths.append(f"fotos/{name}")
    return paths


# --------------------------------------------------------------------------- Klicks

def handle_callback(cb: dict) -> None:
    action, _, betrieb_id = cb.get("data", "").partition(":")
    msg = cb.get("message") or {}
    chat_id = msg.get("chat", {}).get("id")
    message_id = msg.get("message_id")

    # Schutz: nur der Admin darf freigeben, selbst wenn jemand den Bot-Token aus der App zieht.
    if str(cb["from"]["id"]) != str(ADMIN_ID):
        tg_safe("answerCallbackQuery", callback_query_id=cb["id"], text="Nur der Admin darf freigeben.")
        return

    betrieb = parse_betrieb(msg.get("text", ""))
    if betrieb is None or betrieb["id"] != betrieb_id:
        tg_safe("answerCallbackQuery", callback_query_id=cb["id"], text="Daten unlesbar – bitte manuell prüfen.")
        return

    if action == "ok":
        try:
            fotos = download_fotos(betrieb)
        except Exception as e:  # noqa: BLE001 – Betrieb trotzdem freigeben, nur ohne Fotos
            print("Fotos nicht ladbar:", e, file=sys.stderr, flush=True)
            fotos = []
        betrieb.pop("fotoIds", None)
        betrieb["fotos"] = fotos
        entries = upsert(load_list(), betrieb)
        save_list(entries)
        try:
            where = push_to_github(entries, fotos)
        except Exception as e:  # noqa: BLE001 – Fehler dem Admin zeigen statt abstürzen
            where = f"lokal gespeichert, GitHub-Upload fehlgeschlagen: {e}"
        status = f"✅ Freigegeben ({where}, {len(fotos)} Foto(s))"
    else:
        status = "❌ Abgelehnt"

    tg_safe("answerCallbackQuery", callback_query_id=cb["id"], text=status[:190])
    # Buttons entfernen, damit nicht doppelt geklickt wird, und Status als Antwort anhängen.
    tg_safe("editMessageReplyMarkup", chat_id=chat_id, message_id=message_id, reply_markup={"inline_keyboard": []})
    tg_safe("sendMessage", chat_id=chat_id, reply_to_message_id=message_id, text=f"{status}: {betrieb['name']}")
    print(status, betrieb["name"], flush=True)


def run_once() -> None:
    """Alle wartenden Klicks verarbeiten und bei Telegram als erledigt bestätigen."""
    res = tg("getUpdates", timeout=0, allowed_updates=["callback_query"])
    updates = res.get("result", [])
    for update in updates:
        if "callback_query" in update:
            handle_callback(update["callback_query"])
    if updates:
        # Bestätigen, damit dieselben Klicks beim nächsten Lauf nicht nochmal kommen.
        tg("getUpdates", offset=updates[-1]["update_id"] + 1, timeout=0)
    print(f"{len(updates)} Klick(s) verarbeitet.", flush=True)


def main() -> None:
    if not TOKEN or not ADMIN_ID:
        sys.exit("Bitte TELEGRAM_BOT_TOKEN und TELEGRAM_ADMIN_CHAT_ID setzen.")
    if "--once" in sys.argv:
        run_once()
        return
    print("Freigabe-Bot läuft. Warte auf Klicks … (Strg+C zum Beenden)", flush=True)
    offset = 0
    while True:
        try:
            res = tg("getUpdates", offset=offset, timeout=60, allowed_updates=["callback_query"])
            for update in res.get("result", []):
                offset = update["update_id"] + 1
                if "callback_query" in update:
                    handle_callback(update["callback_query"])
        except KeyboardInterrupt:
            break
        except Exception as e:  # noqa: BLE001 – Netz weg o. ä.: kurz warten, weitermachen
            print("Fehler:", e, file=sys.stderr, flush=True)
            time.sleep(5)


if __name__ == "__main__":
    main()
