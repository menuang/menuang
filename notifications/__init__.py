"""Modul pengiriman notifikasi peringatan dini dan circuit breaker (Telegram / Android)."""

from core.risk_manager import RiskEvaluation


def format_risk_alert(evaluation: RiskEvaluation) -> str:
    """Format pesan peringatan risiko untuk dikirim ke Telegram atau Android."""
    return (
        f"🫖 MENUANG RISK ALERT — {evaluation.unit_name}\n"
        f"Status         : {evaluation.level.value}\n"
        f"Rugi Harian    : {evaluation.daily_loss_pct:.2f}%\n"
        f"Drawdown Unit  : {evaluation.cumulative_dd_pct:.2f}%\n"
        f"Buka Posisi    : {'DIIZINKAN' if evaluation.allow_new_positions else 'DIBLOKIR'}\n"
        f"Tindakan       : {evaluation.action_message}"
    )
