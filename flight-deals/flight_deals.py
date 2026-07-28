#!/usr/bin/env python3
"""Chollos de vuelo desde Madrid (Ryanair, sin destino fijo).

Consulta la API pública de "cheapest fares" de Ryanair: findes (salida jue/vie/sab,
2-4 noches) desde MAD a cualquier destino por <= MAX_PRICE eur ida y vuelta.
Solo envia email cuando aparecen chollos NUEVOS (recuerda los ya avisados en
seen_deals.json para no spamear el mismo chollo cada noche).

Config en config.json (no se sube a git):
  {"gmail_user": "tu@gmail.com", "gmail_app_password": "xxxx xxxx xxxx xxxx",
   "to": "ignaciosanbenitop@gmail.com"}
El app password se genera en https://myaccount.google.com/apppasswords
"""
import json
import smtplib
import ssl
import sys
import urllib.parse
import urllib.request
from datetime import date, timedelta
from email.message import EmailMessage
from pathlib import Path

try:  # python.org de macOS no confia en el llavero del sistema; usa certifi si esta
    import certifi
    _CTX = ssl.create_default_context(cafile=certifi.where())
except Exception:
    _CTX = ssl.create_default_context()

ORIGIN = "MAD"
MAX_PRICE = 50.0          # eur, ida y vuelta por persona
WEEKS_AHEAD = 10          # horizonte de busqueda
OUT_DAYS = "THURSDAY,FRIDAY,SATURDAY"
DUR_FROM, DUR_TO = 2, 4   # noches
API = "https://services-api.ryanair.com/farfnd/v4/roundTripFares"

HERE = Path(__file__).resolve().parent
STATE = HERE / "seen_deals.json"
CONFIG = HERE / "config.json"


def fetch():
    today = date.today()
    end = today + timedelta(weeks=WEEKS_AHEAD)
    params = {
        "departureAirportIataCode": ORIGIN,
        "outboundDepartureDateFrom": today.isoformat(),
        "outboundDepartureDateTo": end.isoformat(),
        "inboundDepartureDateFrom": today.isoformat(),
        "inboundDepartureDateTo": (end + timedelta(days=DUR_TO)).isoformat(),
        "durationFrom": DUR_FROM,
        "durationTo": DUR_TO,
        "outboundDepartureDaysOfWeek": OUT_DAYS,
        "currency": "EUR",
        # ponytail: limit max de la API ~20 y offset se ignora; devuelve los mas
        # baratos primero, que es justo lo que queremos. Si algun dia hubiera >20
        # destinos <=50 eur se perderian los del final (improbable en un finde).
        "limit": 20,
    }
    # safe="," -> comas literales en daysOfWeek; con %2C la API devuelve 400
    url = API + "?" + urllib.parse.urlencode(params, safe=",")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=40, context=_CTX) as r:
        return json.load(r)


def deals(data):
    out = []
    for f in data.get("fares", []):
        price = f["summary"]["price"]["value"]
        if price > MAX_PRICE:
            continue
        ob, ib = f["outbound"], f["inbound"]
        out.append({
            "city": ob["arrivalAirport"]["name"],
            "iata": ob["arrivalAirport"]["iataCode"],
            "price": round(price, 2),
            "out": ob["departureDate"][:10],
            "back": ib["departureDate"][:10],
        })
    out.sort(key=lambda d: d["price"])
    return out


def key(d):
    return f'{d["iata"]}|{d["out"]}|{d["back"]}|{d["price"]}'


def load_seen():
    if STATE.exists():
        return set(json.loads(STATE.read_text()))
    return set()


def save_seen(keys):
    # solo guarda chollos cuya fecha de salida sea futura (auto-poda)
    today = date.today().isoformat()
    keep = [k for k in keys if k.split("|")[1] >= today]
    STATE.write_text(json.dumps(sorted(keep), indent=0))


def send_email(cfg, new_deals):
    lines = [
        f'{d["price"]:.2f} eur  {d["city"]:<22} {d["out"]} -> {d["back"]}'
        for d in new_deals
    ]
    text = "Chollos nuevos desde Madrid (Ryanair, ida y vuelta):\n\n" + "\n".join(lines)
    text += "\n\nReserva en ryanair.com. Precios cambian rapido."

    rows = "".join(
        f'<tr><td style="padding:6px 14px 6px 0;font-weight:700;color:#0a7d2c">'
        f'{d["price"]:.2f}&nbsp;€</td>'
        f'<td style="padding:6px 14px 6px 0">{d["city"]}</td>'
        f'<td style="padding:6px 0;color:#555">{d["out"]} &rarr; {d["back"]}</td></tr>'
        for d in new_deals
    )
    html = (
        f'<div style="font-family:-apple-system,Segoe UI,Roboto,sans-serif">'
        f'<h2 style="margin:0 0 4px">✈️ {len(new_deals)} chollo(s) nuevo(s) desde Madrid</h2>'
        f'<p style="color:#666;margin:0 0 14px">Findes de 2-4 noches, ida y vuelta &le; {MAX_PRICE:.0f}&nbsp;€</p>'
        f'<table style="border-collapse:collapse;font-size:15px">{rows}</table>'
        f'<p style="color:#999;font-size:12px;margin-top:16px">Fuente: API Ryanair. Reserva en ryanair.com — vuelan rapido.</p>'
        f'</div>'
    )

    msg = EmailMessage()
    msg["Subject"] = f'✈️ {len(new_deals)} chollo(s) desde Madrid <= {MAX_PRICE:.0f} eur'
    msg["From"] = cfg["gmail_user"]
    msg["To"] = cfg["to"]
    msg.set_content(text)
    msg.add_alternative(html, subtype="html")

    with smtplib.SMTP_SSL("smtp.gmail.com", 465, context=_CTX) as s:
        s.login(cfg["gmail_user"], cfg["gmail_app_password"].replace(" ", ""))
        s.send_message(msg)


def main():
    dry = "--dry-run" in sys.argv
    found = deals(fetch())

    if dry:
        print(f"[dry-run] {len(found)} chollo(s) <= {MAX_PRICE:.0f} eur (no envia email, no toca cache):")
        for d in found:
            print(f'  {d["price"]:.2f} eur  {d["city"]:<22} {d["out"]} -> {d["back"]}')
        return

    if not CONFIG.exists():
        sys.exit(
            "Falta config.json. Copia config.example.json a config.json y rellena "
            "gmail_user, gmail_app_password (https://myaccount.google.com/apppasswords) y to."
        )
    cfg = json.loads(CONFIG.read_text())

    seen = load_seen()
    new = [d for d in found if key(d) not in seen]

    if new:
        send_email(cfg, new)
        print(f"{len(new)} chollo(s) nuevo(s) enviado(s) a {cfg['to']}.")
    else:
        print(f"{len(found)} chollo(s) encontrado(s), 0 nuevos. Sin email.")

    save_seen(seen | {key(d) for d in found})


if __name__ == "__main__":
    main()
