"""Shared utilities for the stacked SMS / notification classifier.

Three models are trained on top of the same feature space:
    1. Spam filter            (assets/spam_model.json)
    2. Transactional gate     (assets/transactional_model.json)
    3. Debit/Credit direction (assets/direction_model.json)

Each model is exported as a small JSON blob (Logistic Regression over
TF-IDF 1-2 grams). The Dart side re-implements tokenisation and inference
in pure Dart and asserts byte-parity against these files via fixture tests.

The preprocessing here MUST stay byte-identical to `lib/services/ml/tfidf_logreg.dart`.
"""
from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report, confusion_matrix, precision_recall_fscore_support
from sklearn.model_selection import train_test_split

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data"
ASSETS_DIR = ROOT / "assets"

# ---------------------------------------------------------------------------
# Preprocessing. Must mirror lib/services/ml/tfidf_logreg.dart exactly.
# ---------------------------------------------------------------------------
_URL_RE = re.compile(
    r"(?:https?://|www\.)\S+|(?:\b[a-z0-9.-]+\.(?:com|in|org|net|co|io|ly|app|link|me)(?:/\S*)?)",
    re.IGNORECASE,
)
_AMT_RE = re.compile(r"(?:₹|rs\.?|inr)\s*[\d,]+(?:\.\d{1,2})?", re.IGNORECASE)
_LONG_NUM_RE = re.compile(r"\d{4,}")
_SHORT_NUM_RE = re.compile(r"\d+")
_NON_WORD_RE = re.compile(r"[^a-z0-9<>\s]")
_WS_RE = re.compile(r"\s+")


def preprocess(text: str) -> str:
    if not text:
        return ""
    t = text.lower()
    t = _URL_RE.sub(" <url> ", t)
    t = _AMT_RE.sub(" <amt> ", t)
    t = _LONG_NUM_RE.sub(" <num> ", t)
    t = _SHORT_NUM_RE.sub(" <d> ", t)
    t = _NON_WORD_RE.sub(" ", t)
    t = _WS_RE.sub(" ", t).strip()
    return t


# ---------------------------------------------------------------------------
# Data loaders.
# ---------------------------------------------------------------------------
def load_spam_corpus() -> pd.DataFrame:
    """Public SMS corpora (spam vs ham) merged and label-normalised."""
    frames: list[pd.DataFrame] = []

    f1 = DATA_DIR / "spam.csv"
    if f1.exists():
        df = pd.read_csv(f1, encoding="latin-1", usecols=[0, 1], names=["label", "text"], header=0)
        df["label"] = df["label"].str.strip().str.lower().map({"ham": 0, "spam": 1})
        frames.append(df.dropna(subset=["label", "text"]))

    f2 = DATA_DIR / "spam_ham_india.csv"
    if f2.exists():
        df = pd.read_csv(f2)
        df = df.rename(columns={"Msg": "text", "Label": "label"})
        df["label"] = df["label"].astype(str).str.strip().str.lower().map({"ham": 0, "spam": 1})
        frames.append(df.dropna(subset=["label", "text"])[["label", "text"]])

    if not frames:
        raise FileNotFoundError(f"No spam datasets found under {DATA_DIR}")
    return pd.concat(frames, ignore_index=True)


def load_upi_corpus() -> pd.DataFrame:
    """Real UPI transactional SMS curated by the app user.

    Files `data/upi*.csv` have columns Msg,Label — all labeled `ham` since
    every row is a genuine completed UPI transaction. The CSVs are
    hand-curated so the message text itself often contains unquoted commas;
    we parse defensively by splitting once on the rightmost comma.
    Direction (debit/credit) is derived from the text for the direction model.
    """
    rows: list[dict] = []
    for p in sorted(DATA_DIR.glob("upi*.csv")):
        with p.open("r", encoding="utf-8", newline="") as f:
            header = True
            for raw in f:
                line = raw.rstrip("\n\r")
                if header:
                    header = False
                    # skip if it looks like a header; otherwise treat as data.
                    if line.lower().startswith("msg"):
                        continue
                if not line.strip() or "," not in line:
                    continue
                text, _, label = line.rpartition(",")
                text = text.strip().strip('"')
                label = label.strip().lower()
                if not text or label not in {"ham", "spam"}:
                    continue
                low = text.lower()
                if "debited" in low:
                    direction = "debit"
                elif "credited" in low:
                    direction = "credit"
                else:
                    direction = None
                rows.append({
                    "text": text,
                    "source": p.name,
                    "direction": direction,
                    "label": label,
                })
    return pd.DataFrame(rows)


# ---------------------------------------------------------------------------
# Synthetic samples — cover banks and apps the user's real data doesn't.
# ---------------------------------------------------------------------------
SYNTHETIC_DEBITS = [
    "Sent Rs.1200.00 From HDFC Bank A/C x1234 To AMAZON PAY On 10/04/26 Ref 204060010123 Not You? Call 18002586161/SMS BLOCK UPI to 7308080808",
    "Sent Rs 349 From HDFC Bank A/C x5678 To SWIGGY On 11/04/26 Ref 204060010200",
    "ICICI Bank Acct XX123 debited for Rs 250.00 on 10-Apr-26; UPI:604123456789. Call 18002662 for dispute.",
    "ICICI Acct XX999 debited Rs 899 on 12-Apr-26 via UPI/Flipkart. UPI Ref 604123456800.",
    "INR 450.00 debited A/c no. XX1234 11-04-26 18:45:22 UPI/P2A/604123456791/ZOMATO. Bal INR 23,456.78.",
    "AXIS BANK: Debit of Rs 1250 from A/c no. XX1234 on 12-04-26. UPI Ref 604123456792 to BLINKIT.",
    "Kotak: Rs 199 debited from your Ac X0987 via UPI to swiggy@okaxis on 10-Apr-26. UPI Ref 604123456793.",
    "PNB: Rs 350.00 debited from A/c XX1234 on 10-04-26 via UPI. Ref 604123456795. Bal Rs 12350.00.",
    "Bank of Baroda: Your A/c XX1234 debited INR 1,299 on 10-APR-26 via UPI@zomato-axis. Ref 604123456796.",
    "Canara Bank: Rs 600 debited from A/c XX1234 on 10-04-26 via UPI. Ref 604123456780.",
    "IOB: Rs.750.00 debited from a/c XX1234 on 10Apr26 UPI/paytm-24hours/604123456798. Bal Rs. 9,250.00",
    "Federal Bank: Rs 1200 dr in a/c XX1234 on 10Apr26 via upi. Ref 604123456799 Bal 15000",
    "You paid Rs 250 to Zomato via UPI. UPI transaction ID 604123456800. From your Google Pay account.",
    "Paid Rs 1,200 to Amazon. Google Pay. UPI Ref: 604123456801",
    "Payment of Rs.250 to swiggy@okhdfcbank successful. PhonePe. Txn ID T2304100012340",
    "Paytm: Paid Rs 350 to Blinkit via UPI. Order ID OID0987654321",
    "BHIM: Rs 100 sent to gaurav@upi successfully. Txn 604123456803",
    "Amazon Pay: Rs 499 debited from your wallet for order #123-4567890-1234567",
    # PhonePe wallet / gift-card payment confirmations. These carry
    # "Not you? Call us" + a top-up URL, which the earlier models
    # mistook for spam — real user messages were being dropped.
    "You've paid Rs.207 via PhonePe gift card to SWIGGY on May 29, 2026 at 9:38:00 PM. Not you? Call us on 022-68727374. Remaining balance Rs.1534.",
    "You've paid Rs. 1000 via PhonePe wallet. Not you? Call us on 022-68727374. Remaining balance: Rs. 3000. To top-up click https://phone.pe/PHONPE/ws",
    "You've paid Rs.1000 via PhonePe Gift Card to Mr.Sharma. Not you? Call us on 022-68727374. To buy Gift Card, click https://phone.pe/PHONPE/4fjyavab",
    "You've paid Rs.190 via PhonePe gift card to Campus canteen on Feb 21, 2026 at 8:01:30 PM. Not you? Call us on 022-68727374. Remaining balance Rs.147.",
    "You've paid Rs.100 via PhonePe wallet for City Mens Parlour. Not you? Call us on 022-68727374. Remaining balance: Rs.2187.5. To top-up click https://phone.pe/PHONPE/ws",
    "You've paid Rs. 180 via PhonePe wallet. Not you? Call us on 022-68727374. Remaining balance: Rs. 2007.5. To top-up click https://phone.pe/PHONPE/ws",
    "You've paid Rs.50 via PhonePe wallet for Ganesh fast food. Not you? Call us on 022-68727374. Remaining balance: Rs.1957.5. To top-up click https://phone.pe/PHONPE/ws",
    "You've paid Rs.85 via PhonePe gift card to H.A Associates on Feb 20, 2026 at 11:02:18 AM. Not you? Call us on 022-68727374. Remaining balance Rs.845.",
    "You've paid Rs. 202 via PhonePe wallet. Not you? Call us on 022-68727374. Remaining balance: Rs. 86.8. To top-up click https://phone.pe/PHONPE/ws",
    "You've paid Rs.55 via PhonePe gift card to Sunrise Electric on Feb 19, 2026 at 6:15:21 PM. Not you? Call us on 022-68727374. Remaining balance Rs.930.",
]

SYNTHETIC_CREDITS = [
    "You've received Rs 5000.00 in HDFC Bank A/c XX1234 via UPI from SURESH KUMAR on 10-Apr-26 Ref 204060010124",
    "HDFC Bank A/c XX1234 credited with Rs 899 on 11-Apr-26 from PRIYA via UPI Ref 204060010301",
    "ICICI Bank: Acct XX123 credited with Rs 1,500.00 on 11-Apr-26. Info: UPI/604123456790/Payment from MEENA SHARMA.",
    "ICICI Acct XX999 credited Rs 2000 on 12-Apr-26 via UPI/RAJESH. Ref 604123456811.",
    "AXIS BANK: Credit of Rs 2,000 to A/c no. XX1234 on 11-04-26. UPI Ref 604123456792 from RAJESH GUPTA.",
    "AXIS: INR 500 credited to A/c XX1234 on 11-04-26 via UPI from NEHA. Ref 604123456820.",
    "Kotak: Rs 400 credited to your A/c X0987 via UPI from amit@okhdfc on 11-Apr-26. UPI Ref 604123456821.",
    "Union Bank: Rs.500.00 credited to A/c XX1234 on 10-Apr-26 by UPI Ref 604123456797 from PRIYA SINGH.",
    "Canara Bank: Rs 2000.00 credited to your A/c XX1234 via UPI on 10-04-26 from RAVI KUMAR. Ref 604123456794.",
    "BoB: Rs 1,299 credited in A/c XX1234 on 10-APR-26 via UPI from ANITA. Ref 604123456822.",
    "You received Rs 500 from Rahul Sharma. Google Pay. UPI Ref: 604123456802",
    "You received Rs 1000 from RAVI on PhonePe. Txn ID T2304100012341.",
    "Paytm: Received Rs 2000 from Priya. UPI ID priya@paytm. Txn ID 123456789012",
    "Google Pay: Rs 850 received from Dinesh. UPI Ref 604123456823.",
    "PhonePe: Rs 1,200 received from RINA. Txn ID T2304100012500",
    "NEFT credit of Rs.25000 received in your A/c XX1234 on 10-04-26 from RAKESH KUMAR, State Bank of India. Ref N123456789012.",
    # Bank refund / tax-refund credits — money genuinely received, but the
    # wording ("IT Refund", "has credit for") differs from UPI credits.
    "Dear Customer, For PAN XXXXXX123L, An IT Refund amount of Rs 11640 for AY-2026-27 has been credited to your account XXXXXXX1234 on 2026-07-11. -SBI",
    "Dear Customer, For PAN XXXXXX987K, An IT Refund amount of Rs 4520 for AY-2025-26 has been credited to your account XXXXXXX9876 on 2026-06-02. -SBI",
    "Your A/C XXXX021234 has credit for ITDTAX REFUND 2026-27 LREPS480 of Rs 11,640.00 on 11/07/26. Avl Bal Rs 79,593.25.-SBI",
    "Your A/C XXXX5678 has credit for ITDTAX REFUND 2025-26 LREPS221 of Rs 2,340.00 on 02/06/26. Avl Bal Rs 12,400.00.-SBI",
]

# Non-transactional bank SMS — informational, promotional that still looks
# legit, OTPs, reminders, bill statements, failed-transaction notices, etc.
NON_TRANSACTIONAL_BANKING = [
    # OTPs
    "Dear Customer, 478912 is your OTP for transaction of Rs 500 on HDFC card ending 1234. Do not share. Valid for 5 min.",
    "123456 is your OTP. Do not share with anyone. -SBI",
    "OTP 987654 for Rs.1,500 txn at AMAZON on card XX1234 valid 10 min. -ICICI",
    "765432 is OTP to add beneficiary in your a/c XX1234. Valid for 5 mins. -AXIS",
    "Use OTP 112233 to login to YONO SBI. Valid till 12:30 pm. Do not share.",
    # Balance / statement
    "Dear Customer, the available balance in your A/c XX1234 as on 10-04-26 is Rs 15,500.00. -SBI",
    "Your A/c XX0587 balance is Rs 3,245.67 as on 12-04-26 17:00. -SBI",
    "Mini-statement A/c XX1234: 10Apr Rs500 DR, 09Apr Rs1000 CR, 08Apr Rs200 DR. Bal Rs 10,000. -HDFC",
    "Your monthly statement for A/c XX1234 is ready. Download at hdfcbank.com/estmt",
    # Bills / reminders
    "Dear Cust, your HDFC CC ending 1234 bill of Rs 5,678 is due on 15-04-26. Pay now to avoid late fee.",
    "Reminder: your SBI Credit Card payment of Rs 2,500 is due tomorrow.",
    "Your electricity bill of Rs 1,250 is due on 20-Apr-26. Pay via BBPS to avoid disconnection.",
    "Dear Customer, your EMI of Rs 8,500 on Loan A/C LN1234 is due on 15-04-26.",
    "Jio: Your plan expires on 15-Apr-26. Recharge Rs 299 to continue services.",
    # Failed / reversed
    "Dear Customer, your UPI payment of Rs 500 to merchant@upi on 10-04-26 FAILED. Any amount debited will be reversed in 3-5 days. -SBI",
    "Your transaction of Rs 250 on card XX1234 was DECLINED on 10-04-26. -HDFC",
    "Payment of Rs 1,000 via UPI was unsuccessful. Amount will be refunded. Ref 604123456999. -ICICI",
    # Card usage (not UPI)
    "Dear Customer, Rs 500 spent on HDFC card XX1234 at SHOP on 10-04-26. Not you? Call 18002586161",
    "ICICI Credit Card XX1234: Rs 1,250 at Swiggy on 10-04-26. Avail credit Rs 45,000.",
    # Generic informational
    "Dear customer, your account has been successfully upgraded to premium. Visit nearest branch for details.",
    "Your KYC is complete. Thank you for banking with us. -SBI",
    "Cheque no 123456 of Rs 10,000 has been cleared in A/c XX1234. -HDFC",
    "Dear customer your debit card has been dispatched and will arrive in 7 working days. -SBI",
    "Your Fixed Deposit of Rs 50,000 has been booked successfully at 7.1% for 12 months. -ICICI",
    # Mandate creation — money has NOT moved yet; the actual debit arrives
    # as a separate SMS. Must be dropped at layer 2.
    "Your UPI-Mandate for Rs.139.00 is successfully created towards Spotify India Pvt Ltd from A/c No: XXXXXX1234. UMN:e728b5d9dd374742889f08faba01421e@ptyes. If not you, kindly report on 18001234. -SBI",
    "Your UPI-Mandate for Rs.499.00 is successfully created towards Netflix Entertainment from A/c No: XXXXXX5678. UMN:ab12cd34ef56@ptaxis. If not you, kindly report on 18001234. -SBI",
    # KYC / account-servicing updates from wallets and banks.
    "KYC record 10085682485845 for Rahul Kumar registered with Central KYC Registry has been updated by PhonePe Wallet on 06/Nov/2025.",
    "Your KYC for PhonePe Wallet is due for renewal. Complete video KYC in the app to continue using wallet services.",
    # Branch feedback / survey requests.
    "Dear Customer, Thank you for the transaction done today at SBI 14538 branch.Plz share your experience on https://crcf.bank.sbi/ccf/home/GetFeedback?TxnDate=291225&TxnType=001010 The feedback may be provided before 8 am tomorrow. No Personal Information would be captured.-SBI",
    # Merchant-device fee terms / offers from payment apps.
    "Monthly fee for your PhonePe device is Rs.125.00, with an offer pricing of Rs.1 subject to terms in PhonePe Business App. One-time set up fee is Rs.318.00 which includes first month Superstar Voice offer.",
    # Wallet / app OTPs.
    "30145 is your one time password to proceed on PhonePe. It is valid for 10 minutes. Do not share your OTP with anyone.",
    "Your OTP for Metro Mobile App is 881993. It is valid for 2 mins. IR/KOLMETRO",
    # Telecom recharge confirmations — the money movement is captured by the
    # separate bank/UPI debit SMS, not this service confirmation.
    "Recharge successful! Plan: 349.0. Jio Number: 6290000000. Benefits: Unlimited 5G data, 56GB (2GB/Day 4G Data), Unlimited Voice, 100 SMS/Day. Validity - 28 Days. Transaction ID HGALP104740962550516.",
    "Recharge of Rs 239 successful on your Airtel number 9800000000. Validity 24 days. Balance data 1.5GB/day.",
]


# ---------------------------------------------------------------------------
# Generic trainer.
# ---------------------------------------------------------------------------
@dataclass
class TrainedModel:
    vocab: dict[str, int]
    idf: np.ndarray
    weights: np.ndarray
    bias: float
    default_threshold: float
    positive_label: str
    negative_label: str


def train_tfidf_logreg(
    texts: Iterable[str],
    labels: Iterable[int],
    *,
    positive_label: str,
    negative_label: str,
    default_threshold: float,
    max_features: int = 3000,
    C: float = 4.0,
    min_df: int = 2,
    title: str = "model",
) -> TrainedModel:
    """Train a binary TF-IDF + Logistic Regression classifier and return its
    JSON-serialisable weights. Also prints an eval summary at several
    thresholds so callers can pick the right `default_threshold`.
    """
    texts_list = [preprocess(t) for t in texts]
    labels_arr = np.asarray(list(labels), dtype=np.int64)
    mask = np.array([len(t) > 0 for t in texts_list])
    texts_list = [t for t, k in zip(texts_list, mask) if k]
    labels_arr = labels_arr[mask]

    stratify = labels_arr if (labels_arr.sum() >= 10 and (len(labels_arr) - labels_arr.sum()) >= 10) else None
    X_tr_raw, X_te_raw, y_tr, y_te = train_test_split(
        texts_list, labels_arr, test_size=0.15, random_state=42, stratify=stratify,
    )

    vec = TfidfVectorizer(
        ngram_range=(1, 2),
        min_df=min_df,
        max_features=max_features,
        sublinear_tf=True,
        norm="l2",
        dtype=np.float32,
        token_pattern=r"\S+",
        lowercase=False,
    )
    X_tr = vec.fit_transform(X_tr_raw)
    X_te = vec.transform(X_te_raw)

    clf = LogisticRegression(C=C, class_weight="balanced", max_iter=2000, solver="liblinear")
    clf.fit(X_tr, y_tr)

    proba = clf.predict_proba(X_te)[:, 1]
    print(f"\n── {title} ── features={len(vec.vocabulary_):,}  train={len(y_tr):,}  test={len(y_te):,}")
    for thr in (0.3, 0.5, 0.7, 0.85, 0.9):
        pred = (proba >= thr).astype(int)
        p, r, f, _ = precision_recall_fscore_support(y_te, pred, average="binary", zero_division=0)
        tn, fp, fn, tp = confusion_matrix(y_te, pred, labels=[0, 1]).ravel()
        marker = " *" if abs(thr - default_threshold) < 1e-9 else ""
        print(
            f"    thr={thr:<4} P={p:.3f} R={r:.3f} F1={f:.3f}  TN={tn} FP={fp} FN={fn} TP={tp}{marker}"
        )
    print(classification_report(
        y_te, (proba >= default_threshold).astype(int),
        target_names=[negative_label, positive_label], zero_division=0, digits=3,
    ))

    vocab = {str(k): int(v) for k, v in vec.vocabulary_.items()}
    return TrainedModel(
        vocab=vocab,
        idf=vec.idf_.astype(np.float32),
        weights=clf.coef_[0].astype(np.float32),
        bias=float(clf.intercept_[0]),
        default_threshold=default_threshold,
        positive_label=positive_label,
        negative_label=negative_label,
    )


def export_model(model: TrainedModel, out_path: Path, *, kind: str) -> None:
    payload = {
        "version": 1,
        "kind": kind,
        "positive_label": model.positive_label,
        "negative_label": model.negative_label,
        "preprocessing": {
            "lowercase": True,
            "replace_url": "<url>",
            "replace_amount": "<amt>",
            "replace_long_number": "<num>",
            "replace_short_number": "<d>",
            "ngram": [1, 2],
            "norm": "l2",
            "sublinear_tf": True,
        },
        "vocab": model.vocab,
        "idf": [float(x) for x in model.idf.tolist()],
        "weights": [float(x) for x in model.weights.tolist()],
        "bias": model.bias,
        "default_threshold": model.default_threshold,
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, separators=(",", ":"))
    size_kb = out_path.stat().st_size / 1024
    print(f"    → wrote {out_path.relative_to(ROOT)} ({size_kb:.1f} KB, {len(model.vocab):,} features)")


def score_sklearn(payload: dict, text: str) -> float:
    """Reference probability computed by sklearn's own TF-IDF transform.

    Rebuilds a TfidfVectorizer from the exported vocab/idf instead of
    re-implementing the maths, so fixtures generated from it check the Dart
    engine against sklearn rather than against a Python copy of the Dart
    code. Empty preprocessed text is the one explicit guard shared by both
    implementations (score 0.0) and is returned as such.
    """
    import numpy as np
    from sklearn.feature_extraction.text import TfidfVectorizer

    clean = preprocess(text)
    if not clean:
        return 0.0
    vec = TfidfVectorizer(
        vocabulary=payload["vocab"],
        ngram_range=(1, 2),
        sublinear_tf=True,
        norm="l2",
        token_pattern=r"\S+",
        lowercase=False,
        dtype=np.float64,
    )
    vec.idf_ = np.asarray(payload["idf"], dtype=np.float64)
    x = vec.transform([clean])
    logit = float((x @ np.asarray(payload["weights"], dtype=np.float64))[0]) + float(payload["bias"])
    return 1.0 / (1.0 + math.exp(-logit))


def score_manual(payload: dict, text: str) -> float:
    """Pure-Python re-implementation of the Dart inference path.
    Used by fixture generators for numerical-parity tests.
    """
    vocab: dict[str, int] = payload["vocab"]
    idf = payload["idf"]
    weights = payload["weights"]
    bias = float(payload["bias"])

    clean = preprocess(text)
    if not clean:
        return 0.0

    tokens = clean.split(" ")
    tf: dict[int, int] = {}
    for i, tok in enumerate(tokens):
        if not tok:
            continue
        idx = vocab.get(tok)
        if idx is not None:
            tf[idx] = tf.get(idx, 0) + 1
        if i + 1 < len(tokens):
            bi = vocab.get(f"{tok} {tokens[i + 1]}")
            if bi is not None:
                tf[bi] = tf.get(bi, 0) + 1
    if not tf:
        return 1.0 / (1.0 + math.exp(-bias))

    raw: dict[int, float] = {}
    norm_sq = 0.0
    for idx, c in tf.items():
        v = (1.0 + math.log(c)) * idf[idx]
        raw[idx] = v
        norm_sq += v * v
    norm = math.sqrt(norm_sq)
    if norm == 0.0:
        return 1.0 / (1.0 + math.exp(-bias))

    logit = bias
    for idx, v in raw.items():
        logit += (v / norm) * weights[idx]
    return 1.0 / (1.0 + math.exp(-logit))
