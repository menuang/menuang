"""Entry point CLI untuk utilitas pemantauan, evaluasi risiko, dan audit Unit Mesin Uang."""

import argparse
import sys
from config import UnitConfig
from core.engine import MenuangEngine
from core.portfolio import UnitPortfolio
from notifications import format_risk_alert


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Menuang — Sistem Monitoring & Manajemen Risiko Unit Mesin Uang (XAUUSD)"
    )
    parser.add_argument(
        "--mode",
        choices=["monitor", "audit"],
        default="monitor",
        help="Mode operasional: 'monitor' untuk evaluasi risiko real-time, 'audit' untuk cek syarat replikasi.",
    )
    parser.add_argument(
        "--pair",
        default="XAUUSD",
        help="Instrumen pasar yang dipantau (default: XAUUSD).",
    )
    parser.add_argument(
        "--initial-capital",
        type=float,
        default=100.0,
        help="Modal awal unit dalam USD (default: 100.0).",
    )
    parser.add_argument(
        "--daily-balance",
        type=float,
        default=100.0,
        help="Saldo awal hari ini dalam USD (default: 100.0).",
    )
    parser.add_argument(
        "--equity",
        type=float,
        default=100.0,
        help="Ekuitas akun saat ini dalam USD (default: 100.0).",
    )
    parser.add_argument(
        "--days-active",
        type=int,
        default=1,
        help="Jumlah hari unit telah berjalan aktif (untuk mode audit).",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    cfg = UnitConfig()

    portfolio = UnitPortfolio(
        unit_name=cfg.unit_name,
        symbol=args.pair,
        initial_capital=args.initial_capital,
        daily_start_balance=args.daily_balance,
        current_equity=args.equity,
        days_active=args.days_active,
    )
    engine = MenuangEngine(config=cfg, portfolio=portfolio)
    evaluation = engine.check_unit_health()

    print("=" * 64)
    print(f"MENUANG — MESIN UANG MONITORING ({cfg.unit_name} | {args.pair})")
    print("=" * 64)
    print(format_risk_alert(evaluation))
    print("-" * 64)

    if args.mode == "audit":
        ready = portfolio.is_ready_for_phase_2_replication() and not evaluation.force_close_all
        print(f"Pertumbuhan Modal : {portfolio.growth_pct:.2f}% (Syarat > 200%)")
        print(f"Hari Aktif        : {portfolio.days_active} hari (Syarat >= 90 hari)")
        print(f"Status Replikasi  : {'SIAP NAIK KE FASE 2' if ready else 'BELUM MEMENUHI SYARAT FASE 2'}")
        print("-" * 64)

    return 0


if __name__ == "__main__":
    sys.exit(main())
