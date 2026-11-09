//+------------------------------------------------------------------+
//|                                            Menuang_EA_XAUUSD.mq5 |
//|                                  Menuang — Ekosistem Mesin Uang  |
//|                                       https://github.com/menuang |
//+------------------------------------------------------------------+
#property copyright   "Menuang (ScalerPip)"
#property link        "https://github.com/menuang"
#property version     "1.00"
#property description "EA Asisten Trading Manual XAUUSD: Auto TP/SL & 3-Layer Daily Risk Guard"

#include <Trade\Trade.mqh>
#include "..\Include\RiskGuard.mqh"

//--- Input Parameter Identitas Unit
input group "=== Identitas Unit Mesin Uang ==="
input string   InpUnitName             = "Unit-01";   // Nama Unit Mesin Uang
input ulong    InpMagicNumber          = 20260921;    // Magic Number (0 = termasuk posisi manual)
input bool     InpManageManualTrades   = true;        // Kelola TP/SL posisi manual (Magic = 0)

//--- Input Parameter Auto TP/SL (Poin XAUUSD)
input group "=== Pengaturan Auto TP / SL ==="
input bool     InpEnableAutoTPSL       = true;        // Aktifkan Auto TP & SL Otomatis
input int      InpStopLossPoints       = 500;         // Stop Loss (dalam Points, 500 = $5.00 di 2 digit)
input int      InpTakeProfitPoints     = 1000;        // Take Profit (dalam Points, 1000 = $10.00 di 2 digit)

//--- Input Parameter Aturan Risiko 3 Lapis (Menuang Standard)
input group "=== Aturan Risiko 3 Lapis Menuang ==="
input double   InpInitialModal         = 100.0;       // Acuan Modal Awal Unit ($)
input double   InpEarlyWarningLossPct  = 15.0;        // Lapis 1: Peringatan Dini (% Rugi Harian)
input double   InpMaxDailyLossPct      = 50.0;        // Lapis 2: Batas Harian Mutlak (% Rugi Harian)
input double   InpMaxCumulativeDDPct   = 70.0;        // Lapis 3: Batas Drawdown Kumulatif (%)
input bool     InpAutoCloseOnHardLimit = true;        // Tutup semua posisi saat menyentuh Lapis 2 / 3

//--- Objek Global
CTrade         g_trade;
CRiskGuard    *g_riskGuard = NULL;
bool           g_unitHalted = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_riskGuard = new CRiskGuard(InpEarlyWarningLossPct,
                                InpMaxDailyLossPct,
                                InpMaxCumulativeDDPct,
                                InpInitialModal);

   PrintFormat("[%s] Menuang_EA_XAUUSD diinisialisasi pada simbol %s. EarlyWarning=%.1f%%, MaxDaily=%.1f%%, MaxDD=%.1f%%",
               InpUnitName, _Symbol, InpEarlyWarningLossPct, InpMaxDailyLossPct, InpMaxCumulativeDDPct);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_riskGuard != NULL)
     {
      delete g_riskGuard;
      g_riskGuard = NULL;
     }
   Comment("");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(g_riskGuard == NULL)
      return;

   ENUM_RISK_STATUS status = g_riskGuard.EvaluateRisk();
   double dailyLossPct     = g_riskGuard.GetDailyLossPct();
   double cumDDPct         = g_riskGuard.GetCumulativeDrawdownPct();

   //--- Periksa Lapis 3 (Drawdown Kumulatif >= 70%) & Lapis 2 (Rugi Harian >= 50%)
   if(status == RISK_MAX_DD_HIT || status == RISK_DAILY_LIMIT_HIT)
     {
      if(!g_unitHalted)
        {
         string reasonMsg = (status == RISK_MAX_DD_HIT)
                            ? StringFormat("DRAWDOWN KUMULATIF %.2f%% >= %.2f%%", cumDDPct, InpMaxCumulativeDDPct)
                            : StringFormat("RUGI HARIAN MUTLAK %.2f%% >= %.2f%%", dailyLossPct, InpMaxDailyLossPct);
         Alert(StringFormat("[%s] CIRCUIT BREAKER AKTIF: %s. Semua aktivitas dihentikan untuk evaluasi!", InpUnitName, reasonMsg));
         if(InpAutoCloseOnHardLimit)
            CloseAllPositions();
         g_unitHalted = true;
        }
     }
   else if(status == RISK_EARLY_WARNING)
     {
      //--- Lapis 1: Peringatan dini 15% (Tidak boleh buka posisi baru, posisi berjalan tetap dikelola TP/SL)
      if(InpEnableAutoTPSL)
         ApplyAutoTPSL();
     }
   else
     {
      g_unitHalted = false;
      if(InpEnableAutoTPSL)
         ApplyAutoTPSL();
     }

   UpdateChartDashboard(status, dailyLossPct, cumDDPct);
  }

//+------------------------------------------------------------------+
//| Fungsi Pemeriksaan Sebelum Membuka Posisi Baru                   |
//+------------------------------------------------------------------+
bool AllowNewTrade()
  {
   if(g_riskGuard == NULL || g_unitHalted)
      return false;

   if(!g_riskGuard.CanOpenNewPosition())
     {
      PrintFormat("[%s] Pembukaan posisi baru ditolak oleh RiskGuard (Rugi Harian: %.2f%%, DD Kumulatif: %.2f%%)",
                  InpUnitName, g_riskGuard.GetDailyLossPct(), g_riskGuard.GetCumulativeDrawdownPct());
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Pasang SL & TP Otomatis pada Posisi yang Belum Memiliki SL/TP    |
//+------------------------------------------------------------------+
void ApplyAutoTPSL()
  {
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      ulong magic = PositionGetInteger(POSITION_MAGIC);
      if(magic != InpMagicNumber && !(InpManageManualTrades && magic == 0))
         continue;

      double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL  = PositionGetDouble(POSITION_SL);
      double currentTP  = PositionGetDouble(POSITION_TP);
      long   posType    = PositionGetInteger(POSITION_TYPE);

      double newSL = currentSL;
      double newTP = currentTP;

      if(posType == POSITION_TYPE_BUY)
        {
         if(currentSL == 0.0 && InpStopLossPoints > 0)
            newSL = NormalizeDouble(openPrice - InpStopLossPoints * point, digits);
         if(currentTP == 0.0 && InpTakeProfitPoints > 0)
            newTP = NormalizeDouble(openPrice + InpTakeProfitPoints * point, digits);
        }
      else if(posType == POSITION_TYPE_SELL)
        {
         if(currentSL == 0.0 && InpStopLossPoints > 0)
            newSL = NormalizeDouble(openPrice + InpStopLossPoints * point, digits);
         if(currentTP == 0.0 && InpTakeProfitPoints > 0)
            newTP = NormalizeDouble(openPrice - InpTakeProfitPoints * point, digits);
        }

      if(newSL != currentSL || newTP != currentTP)
        {
         if(g_trade.PositionModify(ticket, newSL, newTP))
            PrintFormat("[%s] Auto TP/SL diterapkan pada tiket #%I64u (SL: %.*f, TP: %.*f)",
                        InpUnitName, ticket, digits, newSL, digits, newTP);
        }
     }
  }

//+------------------------------------------------------------------+
//| Tutup Semua Posisi Terbuka saat Batas Mutlak Tersentuh           |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      g_trade.PositionClose(ticket);
     }
  }

//+------------------------------------------------------------------+
//| Tampilkan Informasi Status Risiko di Chart MT5                   |
//+------------------------------------------------------------------+
void UpdateChartDashboard(ENUM_RISK_STATUS status, double dailyLossPct, double cumDDPct)
  {
   string statusText = "AMAN (Diizinkan Buka Posisi)";
   if(status == RISK_EARLY_WARNING)
      statusText = "PERINGATAN DINI >= 15% (Stop Buka Posisi Baru)";
   else if(status == RISK_DAILY_LIMIT_HIT)
      statusText = "BATAS HARIAN MUTLAK >= 50% (Semua Berhenti & Evaluasi)";
   else if(status == RISK_MAX_DD_HIT)
      statusText = "BATAS KUMULATIF >= 70% (Unit Dimatikan & Evaluasi)";

   string info = StringFormat(
      "=== MENUANG MESIN UANG [%s] ===\n"
      "Instrumen        : %s\n"
      "Status Risiko    : %s\n"
      "Rugi Harian      : %.2f%% (Peringatan: %.1f%% | Mutlak: %.1f%%)\n"
      "Drawdown Unit    : %.2f%% (Maksimal: %.1f%%)\n"
      "Auto TP/SL       : %s (SL: %d pts | TP: %d pts)",
      InpUnitName,
      _Symbol,
      statusText,
      dailyLossPct, InpEarlyWarningLossPct, InpMaxDailyLossPct,
      cumDDPct, InpMaxCumulativeDDPct,
      InpEnableAutoTPSL ? "AKTIF" : "NONAKTIF",
      InpStopLossPoints, InpTakeProfitPoints
   );
   Comment(info);
  }
//+------------------------------------------------------------------+
