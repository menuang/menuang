"""Konfigurasi sistem dan parameter standar untuk 1 Unit Mesin Uang (Menuang)."""

import os
from dataclasses import dataclass
from dotenv import load_dotenv

load_dotenv()


@dataclass(frozen=True)
class UnitConfig:
    """Konfigurasi identitas, batas risiko, dan kredensial satu Unit Mesin Uang."""

    unit_name: str = os.getenv("UNIT_NAME", "Unit-01")
    symbol: str = os.getenv("SYMBOL", "XAUUSD")
    early_warning_loss_pct: float = float(os.getenv("EARLY_WARNING_LOSS_PCT", "15.0"))
    max_daily_loss_pct: float = float(os.getenv("MAX_DAILY_LOSS_PCT", "50.0"))
    max_cumulative_dd_pct: float = float(os.getenv("MAX_CUMULATIVE_DD_PCT", "70.0"))
    mt5_login: str = os.getenv("MT5_LOGIN", "")
    mt5_server: str = os.getenv("MT5_SERVER", "")
    telegram_bot_token: str = os.getenv("TELEGRAM_BOT_TOKEN", "")
    android_webhook_secret: str = os.getenv("ANDROID_WEBHOOK_SECRET", "")
