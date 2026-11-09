"""Mesin pemantau (Engine) untuk satu Unit Mesin Uang."""

from config import UnitConfig
from core.portfolio import UnitPortfolio
from core.risk_manager import MenuangRiskGuard, RiskEvaluation


class MenuangEngine:
    """Koordinator pemantauan risiko, portofolio, dan status operasional Unit Mesin Uang."""

    def __init__(self, config: UnitConfig, portfolio: UnitPortfolio) -> None:
        self.config = config
        self.portfolio = portfolio
        self.risk_guard = MenuangRiskGuard(
            unit_name=config.unit_name,
            early_warning_loss_pct=config.early_warning_loss_pct,
            max_daily_loss_pct=config.max_daily_loss_pct,
            max_cumulative_dd_pct=config.max_cumulative_dd_pct,
        )

    def check_unit_health(self) -> RiskEvaluation:
        """Jalankan evaluasi risiko terhadap status saldo dan ekuitas terkini."""
        return self.risk_guard.evaluate(
            initial_capital=self.portfolio.initial_capital,
            daily_start_balance=self.portfolio.daily_start_balance,
            current_equity=self.portfolio.current_equity,
        )
