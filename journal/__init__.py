"""Modul pencatatan jurnal transaksi dan audit performa Unit Mesin Uang."""

from dataclasses import dataclass
from datetime import datetime, timezone


@dataclass(frozen=True)
class TradeJournalEntry:
    """Catatan satu transaksi dalam jurnal audit Unit Mesin Uang."""

    timestamp_utc: str
    unit_name: str
    symbol: str
    direction: str
    lot: float
    entry_price: float
    stop_loss: float
    take_profit: float
    profit_usd: float
    notes: str = ""

    @classmethod
    def create_now(
        cls,
        unit_name: str,
        symbol: str,
        direction: str,
        lot: float,
        entry_price: float,
        stop_loss: float,
        take_profit: float,
        profit_usd: float,
        notes: str = "",
    ) -> "TradeJournalEntry":
        return cls(
            timestamp_utc=datetime.now(timezone.utc).isoformat(),
            unit_name=unit_name,
            symbol=symbol,
            direction=direction.upper(),
            lot=lot,
            entry_price=entry_price,
            stop_loss=stop_loss,
            take_profit=take_profit,
            profit_usd=profit_usd,
            notes=notes,
        )
