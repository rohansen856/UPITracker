#!/usr/bin/env python3
"""Generate numerical-parity fixtures for the stacked classifier.

One fixture file per model under `test/fixtures/`:
    spam_fixtures.json
    transactional_fixtures.json
    direction_fixtures.json

Each case contains (text, expected_probability). The Dart test suite loads
the corresponding model JSON and asserts |dart_prob - python_prob| < 1e-4.
If this ever drifts, preprocessing or inference has diverged between Python
and Dart.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
from ml_core import score_manual, score_sklearn  # type: ignore  # noqa: E402

ASSETS = ROOT / "assets"
FIX = ROOT / "test" / "fixtures"
FIX.mkdir(parents=True, exist_ok=True)


def _build(model_file: str, out_name: str, cases: list[dict]) -> None:
    model = json.loads((ASSETS / model_file).read_text(encoding="utf-8"))
    out = []
    for c in cases:
        # The expected value comes from sklearn's transform. score_manual is
        # the Python mirror of the Dart engine; it must agree with sklearn
        # here or the mirror (and likely the Dart code) has drifted.
        ref = score_sklearn(model, c["text"])
        mirror = score_manual(model, c["text"])
        if abs(ref - mirror) > 1e-6:
            raise SystemExit(
                f"{out_name}: score_manual drifted from sklearn on {c['text'][:60]!r}: "
                f"{mirror} vs {ref}"
            )
        out.append({
            "text": c["text"],
            "label": c["label"],
            "probability": ref,
        })
    (FIX / out_name).write_text(
        json.dumps({"cases": out}, indent=2), encoding="utf-8",
    )
    threshold = float(model.get("default_threshold", 0.5))
    wrong = [
        (o["label"], o["text"][:80], o["probability"])
        for o in out
        if (o["label"] == "positive" and o["probability"] < threshold)
        or (o["label"] == "negative" and o["probability"] >= threshold)
    ]
    for w in wrong:
        print(f"  {out_name} mislabeled:", w)
    print(f"Wrote {out_name} ({len(out)} cases, threshold={threshold})")


# --- spam fixtures -----------------------------------------------------------
SPAM_CASES = [
    # positive = spam
    {"label": "positive", "text": "Your account has been credited with a Rs 3,000 bonus, available for withdrawal within 24 hours. Click: cutt.ly/StGmXhY1 NowAssignedL1RBPDA"},
    {"label": "positive", "text": "CONGRATULATIONS! FREE 2GB data is yours! Claim on Airtel Thanks App Now. Hurry i.airtel.in/e/csl_ml_2GB"},
    {"label": "positive", "text": "You have won Rs 5,000 cashback. Click here to claim: http://win.example.com/claim"},
    {"label": "positive", "text": "URGENT: Your KYC has expired. Update OTP at axis-secure.link now to avoid block"},
    {"label": "positive", "text": "Flat 50% off on your next recharge. Use code SAVE50. Visit paytm.com/offer"},
    {"label": "positive", "text": "You are selected for a Rs 1 crore lottery. Send your bank details to claim@win.co"},
    {"label": "positive", "text": "Dear User, You've earned Lifetime Free Kiwi UPI Credit Card (CC: JIOKIWI) on Jio Recharge. Claim now: https://t.jio/JIOCPN/WjSdc9 T&C* JioCoupons"},
    # negative = ham / real tx
    {"label": "negative", "text": "A/C X0587 debited by Rs.50.00 on 11Apr26 trf to M S SURINDER KUM Refno 602560907627 If not u? call-1800111109 for other services-18001234-SBI"},
    {"label": "negative", "text": "Dear UPI User, your A/c XXXXXX0587-credited by Rs.200.00 on 16-04-26 transfer from DIVYANSHUSINGH Ref No 200038012233 -SBI"},
    {"label": "negative", "text": "Sent Rs.1200.00 From HDFC Bank A/C x1234 To AMAZON PAY On 10/04/26 Ref 204060010123"},
    {"label": "negative", "text": "ICICI Bank Acct XX123 debited for Rs 250.00 on 10-Apr-26; UPI:604123456789."},
    {"label": "negative", "text": "You paid Rs 250 to Zomato via UPI. UPI transaction ID 604123456800. From your Google Pay account."},
    {"label": "negative", "text": "You've paid Rs. 1000 via PhonePe wallet. Not you? Call us on 022-68727374. Remaining balance: Rs. 3000. To top-up click https://phone.pe/PHONPE/ws"},
    {"label": "negative", "text": "You've paid Rs.207 via PhonePe gift card to SWIGGY on May 29, 2026 at 9:38:00 PM. Not you? Call us on 022-68727374. Remaining balance Rs.1534."},
    {"label": "negative", "text": "Dear Customer, For PAN XXXXXX123L, An IT Refund amount of Rs 11640 for AY-2026-27 has been credited to your account XXXXXXX1234 on 2026-07-11. -SBI"},
    {"label": "negative", "text": "Hey, can you pick up some milk on the way home?"},
    {"label": "negative", "text": ""},
]

# --- transactional fixtures --------------------------------------------------
TRANSACTIONAL_CASES = [
    # positive = real transaction
    {"label": "positive", "text": "Dear UPI user A/C X0587 debited by 500.00 on date 16Apr26 trf to SANDIP MANDAL Refno 300900907330 If not u? call-1800111109 for other services-18001234-SBI"},
    {"label": "positive", "text": "Dear UPI User, your A/c XXXXXX0587-credited by Rs.200.00 on 16-04-26 transfer from DIVYANSHUSINGH Ref No 200038012233 -SBI"},
    {"label": "positive", "text": "Sent Rs.1200.00 From HDFC Bank A/C x1234 To AMAZON PAY On 10/04/26 Ref 204060010123"},
    {"label": "positive", "text": "You paid Rs 250 to Zomato via UPI. UPI transaction ID 604123456800. From your Google Pay account."},
    {"label": "positive", "text": "ICICI Bank Acct XX123 debited for Rs 250.00 on 10-Apr-26; UPI:604123456789."},
    {"label": "positive", "text": "INR 450.00 debited A/c no. XX1234 11-04-26 18:45:22 UPI/P2A/604123456791/ZOMATO. Bal INR 23,456.78."},
    {"label": "positive", "text": "Paytm: Received Rs 2000 from Priya. UPI ID priya@paytm. Txn ID 123456789012"},
    {"label": "positive", "text": "You've paid Rs. 1000 via PhonePe wallet. Not you? Call us on 022-68727374. Remaining balance: Rs. 3000. To top-up click https://phone.pe/PHONPE/ws"},
    {"label": "positive", "text": "You've paid Rs.207 via PhonePe gift card to SWIGGY on May 29, 2026 at 9:38:00 PM. Not you? Call us on 022-68727374. Remaining balance Rs.1534."},
    {"label": "positive", "text": "You've paid Rs.100 via PhonePe wallet for City Mens Parlour. Not you? Call us on 022-68727374. Remaining balance: Rs.2187.5. To top-up click https://phone.pe/PHONPE/ws"},
    {"label": "positive", "text": "Dear Customer, For PAN XXXXXX123L, An IT Refund amount of Rs 11640 for AY-2026-27 has been credited to your account XXXXXXX1234 on 2026-07-11. -SBI"},
    {"label": "positive", "text": "Your A/C XXXX021234 has credit for ITDTAX REFUND 2026-27 LREPS480 of Rs 11,640.00 on 11/07/26. Avl Bal Rs 79,593.25.-SBI"},
    # negative = non-transactional
    {"label": "negative", "text": "Dear Customer, 478912 is your OTP for transaction of Rs 500 on HDFC card ending 1234. Do not share."},
    {"label": "negative", "text": "Your A/c XX0587 balance is Rs 3,245.67 as on 12-04-26 17:00. -SBI"},
    {"label": "negative", "text": "Dear Cust, your HDFC CC ending 1234 bill of Rs 5,678 is due on 15-04-26. Pay now to avoid late fee."},
    {"label": "negative", "text": "Dear Customer, your UPI payment of Rs 500 to merchant@upi on 10-04-26 FAILED. Any amount debited will be reversed in 3-5 days. -SBI"},
    {"label": "negative", "text": "Your transaction of Rs 250 on card XX1234 was DECLINED on 10-04-26. -HDFC"},
    {"label": "negative", "text": "Hey, can you pick up some milk on the way home?"},
    {"label": "negative", "text": "Meeting rescheduled to 4 PM tomorrow in conference room B."},
    {"label": "negative", "text": "URGENT: Your KYC has expired. Update OTP at axis-secure.link now to avoid block"},
    {"label": "negative", "text": "Your UPI-Mandate for Rs.139.00 is successfully created towards Spotify India Pvt Ltd from A/c No: XXXXXX1234. UMN:e728b5d9dd374742889f08faba01421e@ptyes. If not you, kindly report on 18001234. -SBI"},
    {"label": "negative", "text": "KYC record 10085682485845 for Rahul Kumar registered with Central KYC Registry has been updated by PhonePe Wallet on 06/Nov/2025."},
    {"label": "negative", "text": "30145 is your one time password to proceed on PhonePe. It is valid for 10 minutes. Do not share your OTP with anyone."},
    {"label": "negative", "text": "Recharge successful! Plan: 349.0. Jio Number: 6290000000. Benefits: Unlimited 5G data, 56GB (2GB/Day 4G Data), Unlimited Voice, 100 SMS/Day. Validity - 28 Days. Transaction ID HGALP104740962550516."},
]

# --- direction fixtures (positive = credit, negative = debit) ---------------
DIRECTION_CASES = [
    {"label": "negative", "text": "Dear UPI user A/C X0587 debited by 500.00 on date 16Apr26 trf to SANDIP MANDAL Refno 300900907330 If not u? call-1800111109 for other services-18001234-SBI"},
    {"label": "negative", "text": "Dear UPI user A/C X0587 debited by 20.00 on date 06Apr26 trf to Universal Grocer Refno 300264030291 If not u? call-1800111109 for other services-18001234-SBI"},
    {"label": "negative", "text": "Sent Rs.1200.00 From HDFC Bank A/C x1234 To AMAZON PAY On 10/04/26 Ref 204060010123"},
    {"label": "negative", "text": "ICICI Bank Acct XX123 debited for Rs 250.00 on 10-Apr-26; UPI:604123456789."},
    {"label": "negative", "text": "You paid Rs 250 to Zomato via UPI. UPI transaction ID 604123456800."},
    {"label": "negative", "text": "Paytm: Paid Rs 350 to Blinkit via UPI. Order ID OID0987654321"},
    {"label": "negative", "text": "You've paid Rs. 1000 via PhonePe wallet. Not you? Call us on 022-68727374. Remaining balance: Rs. 3000. To top-up click https://phone.pe/PHONPE/ws"},
    {"label": "negative", "text": "You've paid Rs.207 via PhonePe gift card to SWIGGY on May 29, 2026 at 9:38:00 PM. Not you? Call us on 022-68727374. Remaining balance Rs.1534."},
    {"label": "positive", "text": "Dear UPI User, your A/c XXXXXX0587-credited by Rs.200.00 on 16-04-26 transfer from DIVYANSHUSINGH Ref No 200038012233 -SBI"},
    {"label": "positive", "text": "Dear UPI User, your A/c XXXXXX0587-credited by Rs.80.00 on 16-04-26 transfer from Sayan  Chakraborty Ref No 610696958019 -SBI"},
    {"label": "positive", "text": "You've received Rs 5000.00 in HDFC Bank A/c XX1234 via UPI from SURESH KUMAR on 10-Apr-26 Ref 204060010124"},
    {"label": "positive", "text": "You received Rs 500 from Rahul Sharma. Google Pay. UPI Ref: 604123456802"},
    {"label": "positive", "text": "Paytm: Received Rs 2000 from Priya. UPI ID priya@paytm. Txn ID 123456789012"},
    {"label": "positive", "text": "NEFT credit of Rs.25000 received in your A/c XX1234 on 10-04-26 from RAKESH KUMAR, State Bank of India. Ref N123456789012."},
    {"label": "positive", "text": "Dear Customer, For PAN XXXXXX123L, An IT Refund amount of Rs 11640 for AY-2026-27 has been credited to your account XXXXXXX1234 on 2026-07-11. -SBI"},
    {"label": "positive", "text": "Your A/C XXXX021234 has credit for ITDTAX REFUND 2026-27 LREPS480 of Rs 11,640.00 on 11/07/26. Avl Bal Rs 79,593.25.-SBI"},
]


def main() -> int:
    _build("spam_model.json", "spam_fixtures.json", SPAM_CASES)
    _build("transactional_model.json", "transactional_fixtures.json", TRANSACTIONAL_CASES)
    _build("direction_model.json", "direction_fixtures.json", DIRECTION_CASES)
    return 0


if __name__ == "__main__":
    sys.exit(main())
