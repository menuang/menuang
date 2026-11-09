"""Jembatan (Bridge) integrasi TP/SL otomatis antara Android dan terminal MetaTrader 5."""

import hashlib
import hmac
from dataclasses import dataclass
from typing import Dict, Any


@dataclass(frozen=True)
class TPSLPayload:
    """Struktur perintah modifikasi TP/SL dari perangkat Android."""

    unit_name: str
    ticket: int
    symbol: str
    stop_loss: float
    take_profit: float


class AndroidTPSLBridge:
    """Validator dan penerus sinyal TP/SL otomatis dari perangkat Android ke MT5."""

    def __init__(self, webhook_secret: str = "") -> None:
        self.webhook_secret = webhook_secret

    def verify_signature(self, raw_body: bytes, signature: str) -> bool:
        """Verifikasi tanda tangan HMAC-SHA256 dari permintaan webhook Android."""
        if not self.webhook_secret:
            return False
        expected = hmac.new(
            self.webhook_secret.encode("utf-8"),
            raw_body,
            hashlib.sha256,
        ).hexdigest()
        return hmac.compare_digest(expected, signature)

    def build_mt5_modify_request(self, payload: TPSLPayload) -> Dict[str, Any]:
        """Bangun dictionary request standar MetaTrader 5 (TRADE_ACTION_SLTP)."""
        if payload.stop_loss < 0 or payload.take_profit < 0:
            raise ValueError("Nilai Stop Loss dan Take Profit tidak boleh negatif.")
        return {
            "action": "TRADE_ACTION_SLTP",
            "position": payload.ticket,
            "symbol": payload.symbol,
            "sl": float(payload.stop_loss),
            "tp": float(payload.take_profit),
            "comment": f"Menuang Android Bridge [{payload.unit_name}]",
        }
