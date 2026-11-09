"""Pelacakan kinerja Unit Mesin Uang & syarat kelulusan Fase 1 (Fondasi)."""

from dataclasses import dataclass


@dataclass
class UnitPortfolio:
    """Data saldo, ekuitas, dan metrik konsistensi satu Unit Mesin Uang."""

    unit_name: str
    symbol: str = "XAUUSD"
    initial_capital: float = 100.0
    daily_start_balance: float = 100.0
    current_equity: float = 100.0
    days_active: int = 0
    touched_daily_hard_limit: bool = False

    @property
    def growth_pct(self) -> float:
        """Persentase pertumbuhan modal terhadap modal awal."""
        if self.initial_capital <= 0:
            return 0.0
        return round(((self.current_equity - self.initial_capital) / self.initial_capital) * 100.0, 2)

    def is_ready_for_phase_2_replication(self) -> bool:
        """Periksa syarat naik dari Fase 1 (Fondasi) ke Fase 2 (Replikasi).

        Syarat sesuai README:
        - Modal tumbuh di atas 200%
        - Periode minimum 3 bulan berjalan (>= 90 hari)
        - Drawdown harian tidak pernah menyentuh batas mutlak (50%)
        """
        return (
            self.growth_pct > 200.0
            and self.days_active >= 90
            and not self.touched_daily_hard_limit
        )
