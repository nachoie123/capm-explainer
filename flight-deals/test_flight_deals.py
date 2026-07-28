"""Self-check: filtrado de precio, dedup y auto-poda. Corre: python3 test_flight_deals.py"""
from datetime import date, timedelta
import flight_deals as fd


def _fare(price, iata, out, back):
    return {"summary": {"price": {"value": price}},
            "outbound": {"arrivalAirport": {"name": iata, "iataCode": iata},
                         "departureDate": out + "T06:00:00.000"},
            "inbound": {"departureDate": back + "T20:00:00.000"}}


def test_price_filter_and_sort():
    data = {"fares": [_fare(80, "AAA", "2099-01-01", "2099-01-03"),
                      _fare(30, "BBB", "2099-01-01", "2099-01-03"),
                      _fare(45, "CCC", "2099-01-02", "2099-01-04")]}
    got = fd.deals(data)
    assert [d["iata"] for d in got] == ["BBB", "CCC"], got  # 80 fuera, ordenado por precio


def test_key_is_stable():
    d = {"iata": "BBB", "out": "2099-01-01", "back": "2099-01-03", "price": 30}
    assert fd.key(d) == "BBB|2099-01-01|2099-01-03|30"


def test_save_seen_prunes_past(tmp_path=None):
    yesterday = (date.today() - timedelta(days=1)).isoformat()
    future = (date.today() + timedelta(days=30)).isoformat()
    old = f"AAA|{yesterday}|{yesterday}|20"
    new = f"BBB|{future}|{future}|20"
    fd.STATE = fd.HERE / "seen_test_tmp.json"
    fd.save_seen({old, new})
    kept = fd.load_seen()
    fd.STATE.unlink()
    assert kept == {new}, kept  # poda la salida pasada, conserva la futura


if __name__ == "__main__":
    test_price_filter_and_sort()
    test_key_is_stable()
    test_save_seen_prunes_past()
    print("OK")
