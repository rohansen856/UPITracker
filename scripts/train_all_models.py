#!/usr/bin/env python3
"""Train the three stacked classifiers used by the app.

Layer 1 - spam              assets/spam_model.json
Layer 2 - transactional     assets/transactional_model.json
Layer 3 - direction         assets/direction_model.json

Each model is a tiny TF-IDF + Logistic Regression blob (~150 KB JSON).
Run:
    python3 scripts/train_all_models.py
"""
from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))

from ml_core import (  # type: ignore  # noqa: E402
    ASSETS_DIR,
    NON_TRANSACTIONAL_BANKING,
    SYNTHETIC_CREDITS,
    SYNTHETIC_DEBITS,
    export_model,
    load_spam_corpus,
    load_upi_corpus,
    preprocess,
    train_tfidf_logreg,
)


# ---------------------------------------------------------------------------
# Layer 1 — Spam filter.
# ---------------------------------------------------------------------------
# Curated scam / promotional samples that look transactional ("Rs credited")
# and were the original failure case we built this stack to fix.
CURATED_SPAM = [
    "Your account has been credited with a Rs 3,000 bonus, available for withdrawal within 24 hours. Click: cutt.ly/StGmXhY1 NowAssignedL1RBPDA",
    "Congratulations! Rs 10,000 has been credited to your reward wallet. Claim now: bit.ly/3abcde",
    "You have won Rs 5,000 cashback. Click here to claim: http://win.example.com/claim",
    "Dear User, your loan of Rs 50,000 is pre-approved! Apply now at getloan.in/offer",
    "URGENT: Rs 2,000 bonus credited. Withdraw before 24 hrs via link: tinyurl.com/abc123",
    "Flat 50% off on your next recharge! Use code SAVE50 on paytm. Visit paytm.com/offer",
    "Earn Rs 500 daily from home! Work from anywhere. WhatsApp +91 98765 43210 for details.",
    "Free Rs 100 added to your Paytm wallet. Claim in 1 hour: bit.ly/offer",
    "Your KYC has expired. Update now to avoid account block: secure-kyc.xyz/update",
    "ALERT: Your debit card will be blocked. Update OTP at axis-secure.link to continue",
    "You are selected for a Rs 1 crore lottery. Send your bank details to claim@win.co",
    "Get instant personal loan up to Rs 5 lakh at 1% interest. Apply: loan.xyz",
    "Special offer: Rs 5000 cashback on purchase of smartphone. T&C apply. bit.ly/5k",
    "Congratulations! Rs 25000 credited as part of govt relief scheme. Claim now.",
    "Get Rs 500 free on joining. Refer 5 friends to earn Rs 10000. Download app: play.g/xyz",
    # Coupon / reward promos that mimic payment-confirmation wording
    # ("You've earned …") — must not be confused with "You've paid …".
    "Dear User, You've earned Lifetime Free Kiwi UPI Credit Card (CC: JIOKIWI) on Jio Recharge. Claim now: https://t.jio/JIOCPN/WjSdc9 T&C* JioCoupons",
    "Dear User, You've earned Gadget Lane Exclusive Earbuds at Rs 299! (CC: JIOCOUPONPRO2) on JioRecharge. Claim now: https://t.jio/JIOCPN/GjITQZ T&C* JioCoupons",
    "Dear User, You've earned 20% off on your next DTH recharge (CC: DTHSAVER) on Jio Recharge. Claim now: https://t.jio/JIOCPN/AbCdEf T&C* JioCoupons",
]


def train_spam(upi_real: pd.DataFrame) -> None:
    print("\n" + "=" * 70 + "\n[1/3] SPAM FILTER\n" + "=" * 70)
    df = load_spam_corpus()
    print(f"base corpus: {len(df):,}  (spam={int(df.label.sum())}, ham={int((1-df.label).sum())})")

    # Real UPI transactions → strong HAM signal.
    upi_ham = pd.DataFrame({"text": upi_real["text"].tolist(), "label": 0})
    # Synthetic bank / UPI transactional samples covering HDFC, ICICI, Axis,
    # Kotak, PNB, BoB, Canara, IOB, Federal, GPay, PhonePe, Paytm, BHIM, NEFT.
    # These are critical — without them the user's real SBI messages bias the
    # model so hard toward "SBI-shaped = ham" that an HDFC "Sent Rs.1200…"
    # gets flagged as spam (actually observed during earlier runs).
    synthetic_ham = pd.DataFrame({
        "text": SYNTHETIC_DEBITS + SYNTHETIC_CREDITS,
        "label": 0,
    })
    # Non-transactional banking messages (OTPs, balance alerts, bill
    # reminders, declined transactions) are NOT spam — they should pass
    # layer 1 and get dropped by layer 2. If we don't teach layer 1 this,
    # an OTP that says "OTP for transaction of Rs 500. Do not share" will
    # look too much like a lottery SMS and get mis-classified.
    ntx_ham = pd.DataFrame({
        "text": NON_TRANSACTIONAL_BANKING,
        "label": 0,
    })
    print(f"adding {len(upi_ham):,} real UPI SMS + "
          f"{len(synthetic_ham):,} synthetic bank SMS + "
          f"{len(ntx_ham):,} banking-informational as HAM")

    curated = pd.DataFrame({"text": CURATED_SPAM, "label": 1})

    # Up-weight the real + synthetic transactional HAM so the trainer
    # prioritises "don't kill legit messages" above overall F1.
    df_full = pd.concat(
        [df, upi_ham, synthetic_ham, ntx_ham]
        + [upi_ham] * 2
        + [synthetic_ham] * 4
        + [ntx_ham] * 6
        + [curated] * 2,
        ignore_index=True,
    )
    model = train_tfidf_logreg(
        df_full["text"].astype(str).values,
        df_full["label"].astype(int).values,
        positive_label="spam",
        negative_label="ham",
        default_threshold=0.85,  # conservative — precision > recall
        title="spam filter",
    )
    export_model(model, ASSETS_DIR / "spam_model.json", kind="logreg-tfidf")


def train_transactional(upi_real: pd.DataFrame) -> None:
    print("\n" + "=" * 70 + "\n[2/3] TRANSACTIONAL CLASSIFIER\n" + "=" * 70)

    # Positive: real completed money movement.
    pos_texts: list[str] = upi_real["text"].astype(str).tolist()
    pos_texts += SYNTHETIC_DEBITS + SYNTHETIC_CREDITS
    pos_df = pd.DataFrame({"text": pos_texts, "label": 1})

    # Negative: non-transactional banking + a sample of conversational HAM
    # from the public corpus so the model doesn't just memorise "bank" words.
    spam_ham = load_spam_corpus()
    convo_ham = spam_ham[spam_ham.label == 0].sample(
        n=min(800, (spam_ham.label == 0).sum()), random_state=42,
    )
    # Include spam as negative too — they are NOT transactional.
    promo = spam_ham[spam_ham.label == 1].sample(
        n=min(400, (spam_ham.label == 1).sum()), random_state=42,
    )

    non_tx = pd.concat([
        pd.DataFrame({"text": NON_TRANSACTIONAL_BANKING, "label": 0}),
        # up-weight the curated banking-but-non-tx messages
        pd.DataFrame({"text": NON_TRANSACTIONAL_BANKING * 4, "label": 0}),
        pd.DataFrame({"text": convo_ham["text"].astype(str).values, "label": 0}),
        pd.DataFrame({"text": promo["text"].astype(str).values, "label": 0}),
    ], ignore_index=True)

    full = pd.concat([pos_df, non_tx], ignore_index=True)
    print(f"transactional positives: {int(full.label.sum()):,}  "
          f"negatives: {int((1-full.label).sum()):,}")

    model = train_tfidf_logreg(
        full["text"].astype(str).values,
        full["label"].astype(int).values,
        positive_label="transactional",
        negative_label="other",
        default_threshold=0.5,
        title="transactional classifier",
    )
    export_model(model, ASSETS_DIR / "transactional_model.json", kind="logreg-tfidf")


def train_direction(upi_real: pd.DataFrame) -> None:
    print("\n" + "=" * 70 + "\n[3/3] DIRECTION CLASSIFIER (debit/credit)\n" + "=" * 70)

    # Label: 1 = credit, 0 = debit.
    rows: list[dict] = []
    for _, r in upi_real.iterrows():
        d = r.get("direction")
        if d == "debit":
            rows.append({"text": r["text"], "label": 0})
        elif d == "credit":
            rows.append({"text": r["text"], "label": 1})

    for t in SYNTHETIC_DEBITS:
        rows.append({"text": t, "label": 0})
    for t in SYNTHETIC_CREDITS:
        rows.append({"text": t, "label": 1})

    df = pd.DataFrame(rows)
    # Credits are rarer in the user's SMS history; duplicate to balance.
    credits = df[df.label == 1]
    debits = df[df.label == 0]
    if len(credits) < len(debits):
        factor = max(1, len(debits) // max(1, len(credits)))
        df = pd.concat([debits] + [credits] * factor, ignore_index=True)

    print(f"debits: {int((1-df.label).sum()):,}  credits: {int(df.label.sum()):,}  total: {len(df):,}")

    model = train_tfidf_logreg(
        df["text"].astype(str).values,
        df["label"].astype(int).values,
        positive_label="credit",
        negative_label="debit",
        default_threshold=0.5,
        # smaller vocab — this task is mostly a few keywords
        max_features=1500,
        title="direction (debit vs credit)",
    )
    export_model(model, ASSETS_DIR / "direction_model.json", kind="logreg-tfidf")


def main() -> int:
    upi_real = load_upi_corpus()
    print(f"loaded {len(upi_real):,} real UPI SMS  "
          f"(debit={(upi_real.direction == 'debit').sum()}, "
          f"credit={(upi_real.direction == 'credit').sum()})")

    train_spam(upi_real)
    train_transactional(upi_real)
    train_direction(upi_real)

    print("\nAll models exported under assets/:")
    for p in sorted(ASSETS_DIR.glob("*_model.json")):
        kb = p.stat().st_size / 1024
        print(f"  - {p.name}  ({kb:.1f} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
