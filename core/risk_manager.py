"""Implementasi Aturan Risiko 3 Lapis Menuang (Air -> Teko -> Cangkir).

Aturan Risiko Menuang:
1. Peringatan dini      : Rugi harian mencapai 15% -> berhenti membuka posisi baru
2. Batas harian mutlak  : Rugi harian mencapai 50% -> semua berhenti, lalu evaluasi
3. Batas kumulatif      : Drawdown mencapai 70%    -> unit dimatikan dan dievaluasi
"""

from dataclasses import dataclass
from enum import Enum


class RiskLevel(str, Enum):
    """Status lapisan risiko pada satu Unit Mesin Uang."""

    SAFE = "SAFE"
    EARLY_WARNING = "EARLY_WARNING"
    DAILY_HARD_LIMIT = "DAILY_HARD_LIMIT"
    CUMULATIVE_SHUTDOWN = "CUMULATIVE_SHUTDOWN"


@dataclass(frozen=True)
class RiskEvaluation:
    """Hasil evaluasi kondisi risiko akun saat ini."""

    unit_name: str
    level: RiskLevel
    daily_loss_pct: float
    cumulative_dd_pct: float
    allow_new_positions: bool
    force_close_all: bool
    shutdown_unit: bool
    action_message: str


class MenuangRiskGuard:
    """Penjaga aturan risiko 3 lapis untuk satu Unit Mesin Uang (Cangkir)."""

    def __init__(
        self,
        unit_name: str = "Unit-01",
        early_warning_loss_pct: float = 15.0,
        max_daily_loss_pct: float = 50.0,
        max_cumulative_dd_pct: float = 70.0,
    ) -> None:
        if not (0 < early_warning_loss_pct < max_daily_loss_pct <= 100):
            raise ValueError("Konfigurasi batas rugi harian tidak valid.")
        if not (0 < max_cumulative_dd_pct <= 100):
            raise ValueError("Konfigurasi batas drawdown kumulatif tidak valid.")

        self.unit_name = unit_name
        self.early_warning_loss_pct = early_warning_loss_pct
        self.max_daily_loss_pct = max_daily_loss_pct
        self.max_cumulative_dd_pct = max_cumulative_dd_pct

    @staticmethod
    def calculate_loss_pct(reference_balance: float, current_equity: float) -> float:
        """Hitung persentase penurunan ekuitas terhadap saldo acuan."""
        if reference_balance <= 0:
            raise ValueError("Saldo acuan harus lebih besar dari 0.")
        loss = reference_balance - current_equity
        if loss <= 0:
            return 0.0
        return round((loss / reference_balance) * 100.0, 2)

    def evaluate(
        self,
        initial_capital: float,
        daily_start_balance: float,
        current_equity: float,
    ) -> RiskEvaluation:
        """Evaluasi 3 lapisan aturan risiko Menuang berdasarkan modal awal, saldo harian, dan ekuitas."""
        daily_loss_pct = self.calculate_loss_pct(daily_start_balance, current_equity)
        cumulative_dd_pct = self.calculate_loss_pct(initial_capital, current_equity)

        # Lapisan 3: Batas kumulatif (Drawdown >= 70% -> unit dimatikan dan dievaluasi)
        if cumulative_dd_pct >= self.max_cumulative_dd_pct:
            return RiskEvaluation(
                unit_name=self.unit_name,
                level=RiskLevel.CUMULATIVE_SHUTDOWN,
                daily_loss_pct=daily_loss_pct,
                cumulative_dd_pct=cumulative_dd_pct,
                allow_new_positions=False,
                force_close_all=True,
                shutdown_unit=True,
                action_message=(
                    f"[{self.unit_name}] BATAS KUMULATIF TERSENTUH: Drawdown {cumulative_dd_pct:.2f}% "
                    f"(>= {self.max_cumulative_dd_pct:.1f}%). Unit dimatikan dan wajib dievaluasi penuh!"
                ),
            )

        # Lapisan 2: Batas harian mutlak (Rugi harian >= 50% -> semua berhenti, lalu evaluasi)
        if daily_loss_pct >= self.max_daily_loss_pct:
            return RiskEvaluation(
                unit_name=self.unit_name,
                level=RiskLevel.DAILY_HARD_LIMIT,
                daily_loss_pct=daily_loss_pct,
                cumulative_dd_pct=cumulative_dd_pct,
                allow_new_positions=False,
                force_close_all=True,
                shutdown_unit=False,
                action_message=(
                    f"[{self.unit_name}] BATAS HARIAN MUTLAK TERSENTUH: Rugi harian {daily_loss_pct:.2f}% "
                    f"(>= {self.max_daily_loss_pct:.1f}%). Semua aktivitas dihentikan untuk evaluasi!"
                ),
            )

        # Lapisan 1: Peringatan dini (Rugi harian >= 15% -> berhenti membuka posisi baru)
        if daily_loss_pct >= self.early_warning_loss_pct:
            return RiskEvaluation(
                unit_name=self.unit_name,
                level=RiskLevel.EARLY_WARNING,
                daily_loss_pct=daily_loss_pct,
                cumulative_dd_pct=cumulative_dd_pct,
                allow_new_positions=False,
                force_close_all=False,
                shutdown_unit=False,
                action_message=(
                    f"[{self.unit_name}] PERINGATAN DINI: Rugi harian {daily_loss_pct:.2f}% "
                    f"(>= {self.early_warning_loss_pct:.1f}%). Berhenti membuka posisi baru hari ini."
                ),
            )

        # Status Aman: Teko mengisi cangkir sesuai kapasitasnya
        return RiskEvaluation(
            unit_name=self.unit_name,
            level=RiskLevel.SAFE,
            daily_loss_pct=daily_loss_pct,
            cumulative_dd_pct=cumulative_dd_pct,
            allow_new_positions=True,
            force_close_all=False,
            shutdown_unit=False,
            action_message=(
                f"[{self.unit_name}] AMAN: Rugi harian {daily_loss_pct:.2f}%, "
                f"Drawdown kumulatif {cumulative_dd_pct:.2f}%. Diizinkan membuka posisi sesuai SOP."
            ),
        )
