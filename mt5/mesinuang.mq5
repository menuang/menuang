//+------------------------------------------------------------------+
//|                                                    MesinUang.mq5 |
//|  Mesin Uang (versi sederhana, berbasis kode asli v5)             |
//|  Pemicu Candle/Crossing + Reverse Martingale + Kunci Pra-SL      |
//|                                      https://sagu.pages.dev     |
//+------------------------------------------------------------------+
#property copyright   "Mochamad Tabrani & Antigravity AI"
#property link        "https://sagu.pages.dev"
#property version     "5.10"
#property description "Mesin Uang: Reverse Martingale sederhana, tanpa state tersimpan"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| [1] Parameter Input                                              |
//+------------------------------------------------------------------+
enum ENUM_TRIGGER_MODE
{
   TRIGGER_CANDLE   = 0,   // Candle: close kotak naik = BUY, turun = SELL
   TRIGGER_CROSSING = 1    // Crossing level angka bulat
};

input group "=== PENGATURAN STRATEGI UTAMA ==="
input bool              InpEnableBot      = true;            // Aktifkan Robot Otomatis?
input ENUM_TRIGGER_MODE InpTriggerMode    = TRIGGER_CANDLE;  // Pemicu entri siklus baru
input ENUM_TIMEFRAMES   InpTriggerTF      = PERIOD_M1;       // Timeframe kotak (mode Candle)
input double            InpStartLot       = 0.01;            // Lot Dasar Awal (Step 1)
input double            InpLotMultiplier  = 2.0;             // Faktor Pengali Martingale
input int               InpMaxSteps       = 6;               // Batas Maksimal Step Pembalikan
input double            InpPriceInterval  = 1.0;             // Jarak Level Angka Bulat (mode Crossing)
input double            InpTargetDistance = 1.0;             // Jarak TP & SL dari Entry (harga)
input bool              InpHedgeOnMaxStep = true;            // Kunci Hedge 1:1 sebelum SL step terakhir?
input double            InpLockTriggerPct = 80.0;            // Kunci aktif saat rugi mencapai % jarak SL

input group "=== PENGATURAN NOTIFIKASI & BROKER ==="
input bool              InpEnableAlert    = true;            // Popup Alert di Layar MT5?
input bool              InpEnablePush     = false;           // Notifikasi ke HP (MetaQuotes ID)?
input int               InpSlippage       = 50;              // Toleransi Slippage (pts)
input long              InpMagicBot       = 888100;          // Magic Number Bot (hedge = Magic + 1)

//+------------------------------------------------------------------+
//| [2] Variabel Global                                              |
//+------------------------------------------------------------------+
CTrade            g_trade;
double            g_point;
int               g_digits;
long              g_magicHedge;
bool              g_canHedge        = true;

int               g_currentStep     = 1;
double            g_currentBotLot   = 0.01;
bool              g_isHedgeLocked   = false;
ulong             g_lastManagedDeal = 0;
double            g_lastPrice       = 0.0;
double            g_lastDist        = 0.0;
datetime          g_lastBarTime     = 0;

int               g_pendingDir      = -1;   // -1 tidak ada, 0 BUY, 1 SELL
int               g_failCount       = 0;
uint              g_lastTryMs       = 0;
uint              g_lastLockMs      = 0;

//+------------------------------------------------------------------+
//| [3] Lifecycle                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   g_point         = _Point;
   g_digits        = _Digits;
   g_magicHedge    = InpMagicBot + 1;
   g_currentBotLot = NormalizeLotSize(InpStartLot);
   g_currentStep   = 1;
   g_isHedgeLocked = false;
   g_pendingDir    = -1;
   g_lastPrice     = 0.0;
   g_lastBarTime   = 0;

   g_trade.SetExpertMagicNumber(InpMagicBot);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(GetOptimalFilling(_Symbol));

   g_canHedge = (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   if(InpHedgeOnMaxStep && !g_canHedge)
      Print("Mesin Uang: akun bukan tipe HEDGING, kunci hedge tidak aktif.");

   Print("=== Mesin Uang (Simple) Aktif ===");
   UpdateChartComment();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Comment("");
   Print("=== Mesin Uang Dihentikan ===");
}

//+------------------------------------------------------------------+
//| [4] Eksekusi Tiap Tick                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   if(InpEnableBot)
   {
      if(g_isHedgeLocked)
      {
         CheckUnlock();
      }
      else
      {
         CheckPreSLLock();
         if(g_pendingDir >= 0)                     ProcessPending();
         else if(InpTriggerMode == TRIGGER_CANDLE) CheckCandleTrigger();
         else                                      CheckDirectionalCrossing();
      }
   }

   UpdateChartComment();
}

//+------------------------------------------------------------------+
//| [5a] Pemicu Candle: kotak baru, lihat kotak yang baru tutup      |
//+------------------------------------------------------------------+
void CheckCandleTrigger()
{
   datetime barTime = iTime(_Symbol, InpTriggerTF, 0);
   if(barTime == 0) return;

   if(g_lastBarTime == 0)          // tick pertama: catat saja
   {
      g_lastBarTime = barTime;
      return;
   }
   if(barTime == g_lastBarTime) return;
   g_lastBarTime = barTime;        // kotak baru (detik 00)

   if(CountPositions(InpMagicBot) > 0 || CountPositions(g_magicHedge) > 0) return;

   double o = iOpen(_Symbol, InpTriggerTF, 1);
   double c = iClose(_Symbol, InpTriggerTF, 1);

   if(c > o)
   {
      Print(StringFormat("[KOTAK NAIK] Open %.*f Close %.*f -> BUY", g_digits, o, g_digits, c));
      OpenBotOrder(POSITION_TYPE_BUY, g_currentBotLot);
   }
   else if(c < o)
   {
      Print(StringFormat("[KOTAK TURUN] Open %.*f Close %.*f -> SELL", g_digits, o, g_digits, c));
      OpenBotOrder(POSITION_TYPE_SELL, g_currentBotLot);
   }
}

//+------------------------------------------------------------------+
//| [5b] Pemicu Crossing Level Angka Bulat                           |
//+------------------------------------------------------------------+
void CheckDirectionalCrossing()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(CountPositions(InpMagicBot) > 0 || CountPositions(g_magicHedge) > 0)
   {
      g_lastPrice = bid;
      return;
   }

   if(g_lastPrice <= 0.0)
   {
      g_lastPrice = bid;
      return;
   }

   double step = (InpPriceInterval > 0) ? InpPriceInterval : 1.0;

   double levelUp = MathFloor(bid / step) * step;
   if(g_lastPrice < levelUp && bid >= levelUp)
   {
      g_lastPrice = bid;
      Print(StringFormat("[CROSSING BUY] Melintas naik level %.2f", levelUp));
      OpenBotOrder(POSITION_TYPE_BUY, g_currentBotLot);
      return;
   }

   double levelDown = MathCeil(bid / step) * step;
   if(g_lastPrice > levelDown && bid <= levelDown)
   {
      g_lastPrice = bid;
      Print(StringFormat("[CROSSING SELL] Melintas turun level %.2f", levelDown));
      OpenBotOrder(POSITION_TYPE_SELL, g_currentBotLot);
      return;
   }

   g_lastPrice = bid;
}

//+------------------------------------------------------------------+
//| [6] Transaksi: Kalibrasi & Reverse Martingale                    |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong dealTicket = trans.deal;
   if(dealTicket == 0 || !HistoryDealSelect(dealTicket)) return;

   string sym   = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   long   magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(sym != _Symbol || magic != InpMagicBot) return;   // hedge (magic+1) diabaikan

   long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   long dealType  = HistoryDealGetInteger(dealTicket, DEAL_TYPE);

   if(dealEntry == DEAL_ENTRY_IN)
   {
      ulong  posTicket   = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      double exactPrice  = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      ENUM_POSITION_TYPE pType = (dealType == DEAL_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      CalibratePositionTPSL(posTicket, exactPrice, pType);
      return;
   }

   if(dealEntry == DEAL_ENTRY_OUT)
   {
      if(dealTicket == g_lastManagedDeal) return;
      g_lastManagedDeal = dealTicket;
      HandleClosedDeal(dealTicket, dealType);
   }
}

void HandleClosedDeal(ulong dealTicket, long dealType)
{
   long   reason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
   double net    = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                 + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION)
                 + HistoryDealGetDouble(dealTicket, DEAL_SWAP);

   if(g_isHedgeLocked)
   {
      Print(StringFormat("Posisi tertutup saat terkunci. Hasil bersih: %.2f", net));
      return;
   }

   ENUM_POSITION_TYPE origType = (dealType == DEAL_TYPE_SELL) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

   if(reason == DEAL_REASON_TP)
   {
      string msg = StringFormat("[STEP %d TP] Hasil bersih %.2f. Reset ke Step 1, lanjut searah.", g_currentStep, net);
      Print(msg);
      if(InpEnableAlert) Alert(msg);

      g_currentStep   = 1;
      g_currentBotLot = NormalizeLotSize(InpStartLot);
      StartOrQueue(origType);
   }
   else if(reason == DEAL_REASON_SL)
   {
      if(g_currentStep >= InpMaxSteps)
      {
         string msg = StringFormat("[STEP %d SL] Step maksimal kena SL (hasil bersih %.2f). Siklus direset ke Step 1.", g_currentStep, net);
         Print(msg);
         if(InpEnableAlert) Alert(msg);
         if(InpEnablePush)  SendNotification(msg);

         g_currentStep   = 1;
         g_currentBotLot = NormalizeLotSize(InpStartLot);
         g_pendingDir    = -1;
         return;
      }

      g_currentStep++;
      g_currentBotLot = NormalizeLotSize(g_currentBotLot * InpLotMultiplier);

      string msg = StringFormat("[STEP %d SL] Hasil bersih %.2f. Balik arah ke Step %d (Lot %.2f).",
                                g_currentStep - 1, net, g_currentStep, g_currentBotLot);
      Print(msg);
      if(InpEnableAlert) Alert(msg);

      StartOrQueue((origType == POSITION_TYPE_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY);
   }
   else
   {
      // Stop out / ditutup manual: jangan lanjutkan rantai
      Print(StringFormat("Posisi ditutup bukan oleh TP/SL (alasan %d, hasil bersih %.2f). Siklus direset ke Step 1.", (int)reason, net));
      g_currentStep   = 1;
      g_currentBotLot = NormalizeLotSize(InpStartLot);
      g_pendingDir    = -1;
   }
}

// Coba buka langsung; kalau gagal, antrikan dan coba lagi di OnTick
void StartOrQueue(ENUM_POSITION_TYPE type)
{
   if(!InpEnableBot) return;
   g_failCount = 0;
   if(!OpenBotOrder(type, g_currentBotLot))
      g_pendingDir = (type == POSITION_TYPE_BUY) ? 0 : 1;
   else
      g_pendingDir = -1;
}

void ProcessPending()
{
   if(CountPositions(InpMagicBot) > 0) return;

   uint now = GetTickCount();
   if(now - g_lastTryMs < 1000) return;
   g_lastTryMs = now;

   ENUM_POSITION_TYPE t = (g_pendingDir == 0) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   if(OpenBotOrder(t, g_currentBotLot))
   {
      g_pendingDir = -1;
      g_failCount  = 0;
      return;
   }

   g_failCount++;
   if(g_failCount >= 5)
   {
      string msg = StringFormat("Order Step %d gagal 5x (margin/koneksi). Siklus direset ke Step 1.", g_currentStep);
      Print(msg);
      if(InpEnableAlert) Alert(msg);
      g_pendingDir    = -1;
      g_failCount     = 0;
      g_currentStep   = 1;
      g_currentBotLot = NormalizeLotSize(InpStartLot);
   }
}

//+------------------------------------------------------------------+
//| [7] Kalibrasi TP/SL Pasca-Eksekusi                               |
//+------------------------------------------------------------------+
void CalibratePositionTPSL(ulong posTicket, double exactPrice, ENUM_POSITION_TYPE posType)
{
   if(!PositionSelectByTicket(posTicket)) return;

   double dist    = (g_lastDist > 0.0) ? g_lastDist : InpTargetDistance;
   double exactTP = (posType == POSITION_TYPE_BUY) ? (exactPrice + dist) : (exactPrice - dist);
   double exactSL = (posType == POSITION_TYPE_BUY) ? (exactPrice - dist) : (exactPrice + dist);
   exactTP = NormalizeDouble(exactTP, g_digits);
   exactSL = NormalizeDouble(exactSL, g_digits);

   double currentTP = PositionGetDouble(POSITION_TP);
   double currentSL = PositionGetDouble(POSITION_SL);

   if(MathAbs(currentTP - exactTP) > (g_point * 0.1) || MathAbs(currentSL - exactSL) > (g_point * 0.1))
   {
      g_trade.SetExpertMagicNumber(InpMagicBot);
      if(g_trade.PositionModify(posTicket, exactSL, exactTP) && RetcodeOK(g_trade.ResultRetcode()))
         Print(StringFormat("[KALIBRASI] Tiket #%I64u | Entry %.*f | TP %.*f | SL %.*f",
                            posTicket, g_digits, exactPrice, g_digits, exactTP, g_digits, exactSL));
      else
         Print(StringFormat("Kalibrasi tiket #%I64u gagal (kode %u), TP/SL awal dipertahankan.",
                            posTicket, g_trade.ResultRetcode()));
   }
}

//+------------------------------------------------------------------+
//| [8] Eksekutor Order                                              |
//+------------------------------------------------------------------+
double GetDist()
{
   double stopLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point;
   double spread  = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double need    = stopLvl + spread + 2.0 * g_point;
   double dist    = (InpTargetDistance > 0) ? InpTargetDistance : 1.0;
   return MathMax(dist, need);
}

bool OpenBotOrder(ENUM_POSITION_TYPE type, double lot)
{
   lot = NormalizeLotSize(lot);
   double dist = NormalizeDouble(GetDist(), g_digits);
   g_lastDist  = dist;

   g_trade.SetExpertMagicNumber(InpMagicBot);
   string cmt = StringFormat("MesinUang %s S%d", (type == POSITION_TYPE_BUY) ? "BUY" : "SELL", g_currentStep);
   bool ok;

   if(type == POSITION_TYPE_BUY)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(!HasMargin(ORDER_TYPE_BUY, lot, ask)) { Print("Margin tidak cukup untuk BUY lot ", DoubleToString(lot, 2)); return false; }
      ok = g_trade.Buy(lot, _Symbol, ask, NormalizeDouble(ask - dist, g_digits), NormalizeDouble(ask + dist, g_digits), cmt);
   }
   else
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(!HasMargin(ORDER_TYPE_SELL, lot, bid)) { Print("Margin tidak cukup untuk SELL lot ", DoubleToString(lot, 2)); return false; }
      ok = g_trade.Sell(lot, _Symbol, bid, NormalizeDouble(bid + dist, g_digits), NormalizeDouble(bid - dist, g_digits), cmt);
   }

   if(!ok || !RetcodeOK(g_trade.ResultRetcode()))
   {
      Print(StringFormat("Order gagal. Kode: %u (%s)", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription()));
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| [9] Kunci Hedge 1:1 sebelum SL step terakhir                     |
//+------------------------------------------------------------------+
void CheckPreSLLock()
{
   if(!InpHedgeOnMaxStep || !g_canHedge) return;
   if(g_currentStep < InpMaxSteps) return;

   ulong ticket = GetBotPositionTicket();
   if(ticket == 0 || !PositionSelectByTicket(ticket)) return;

   double sl = PositionGetDouble(POSITION_SL);
   if(sl <= 0.0) return;

   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double vol  = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   double slDist = MathAbs(open - sl);
   if(slDist <= 0.0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double adverse = (ptype == POSITION_TYPE_BUY) ? (open - bid) : (ask - open);

   double pct = MathMax(10.0, MathMin(95.0, InpLockTriggerPct));
   if(adverse < slDist * pct / 100.0) return;

   uint now = GetTickCount();
   if(now - g_lastLockMs < 2000) return;
   g_lastLockMs = now;

   ExecuteLock(ticket, ptype, vol);
}

void ExecuteLock(ulong ticket, ENUM_POSITION_TYPE ptype, double vol)
{
   double hedgeLot = NormalizeLotSize(vol);
   bool ok;

   g_trade.SetExpertMagicNumber(g_magicHedge);
   if(ptype == POSITION_TYPE_BUY)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(!HasMargin(ORDER_TYPE_SELL, hedgeLot, bid)) { g_trade.SetExpertMagicNumber(InpMagicBot); Print("Margin tidak cukup untuk kunci hedge."); return; }
      ok = g_trade.Sell(hedgeLot, _Symbol, bid, 0, 0, "MesinUang LOCK");
   }
   else
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(!HasMargin(ORDER_TYPE_BUY, hedgeLot, ask)) { g_trade.SetExpertMagicNumber(InpMagicBot); Print("Margin tidak cukup untuk kunci hedge."); return; }
      ok = g_trade.Buy(hedgeLot, _Symbol, ask, 0, 0, "MesinUang LOCK");
   }
   g_trade.SetExpertMagicNumber(InpMagicBot);

   if(!ok || !RetcodeOK(g_trade.ResultRetcode()))
   {
      Print(StringFormat("Kunci hedge gagal. Kode: %u (%s)", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription()));
      return;
   }

   // Lepas SL/TP posisi utama agar hedge tidak tertinggal telanjang
   bool removed = false;
   for(int i = 0; i < 3 && !removed; i++)
   {
      if(PositionSelectByTicket(ticket))
         removed = (g_trade.PositionModify(ticket, 0.0, 0.0) && RetcodeOK(g_trade.ResultRetcode()));
      else
         removed = true;
   }
   if(!removed)
      Alert("PERINGATAN: SL posisi utama belum bisa dilepas. Cek manual posisi Mesin Uang sekarang!");

   g_isHedgeLocked = true;
   g_pendingDir    = -1;

   string msg = StringFormat("[KUNCI HEDGE 1:1] Step %d terkunci (lot %.2f). Tutup kedua posisi secara manual.", g_currentStep, hedgeLot);
   Print(msg);
   if(InpEnableAlert) Alert(msg);
   if(InpEnablePush)  SendNotification(msg);
}

// Bot lanjut lagi (Step 1) setelah operator menutup semua posisi
void CheckUnlock()
{
   if(CountPositions(InpMagicBot) + CountPositions(g_magicHedge) > 0) return;

   g_isHedgeLocked = false;
   g_currentStep   = 1;
   g_currentBotLot = NormalizeLotSize(InpStartLot);
   g_pendingDir    = -1;
   g_lastPrice     = 0.0;
   Print("Posisi kosong. Siklus direset, Mesin Uang aktif kembali di Step 1.");
}

//+------------------------------------------------------------------+
//| [10] Helper                                                      |
//+------------------------------------------------------------------+
int CountPositions(long magic)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
         count++;
   }
   return count;
}

ulong GetBotPositionTicket()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicBot)
         return t;
   }
   return 0;
}

bool RetcodeOK(uint code)
{
   return (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_DONE_PARTIAL || code == TRADE_RETCODE_PLACED);
}

bool HasMargin(ENUM_ORDER_TYPE type, double lot, double price)
{
   double margin = 0.0;
   if(!OrderCalcMargin(type, _Symbol, lot, price, margin)) return false;
   return (AccountInfoDouble(ACCOUNT_MARGIN_FREE) >= margin * 1.2);
}

ENUM_ORDER_TYPE_FILLING GetOptimalFilling(string symbol)
{
   uint filling = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   if((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}

double NormalizeLotSize(double lot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0) stepLot = 0.01;

   int dig = 0;
   double s = stepLot;
   while(dig < 8 && MathAbs(s - MathRound(s)) > 1e-8) { s *= 10.0; dig++; }

   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);
   return NormalizeDouble(MathRound(lot / stepLot) * stepLot, dig);
}

//+------------------------------------------------------------------+
//| [11] Status di Chart                                             |
//+------------------------------------------------------------------+
void UpdateChartComment()
{
   string status;
   if(!InpEnableBot)
      status = "NONAKTIF";
   else if(g_isHedgeLocked)
      status = "TERKUNCI HEDGE 1:1 (tutup posisi manual untuk lanjut)";
   else if(g_pendingDir >= 0)
      status = StringFormat("MENUNGGU EKSEKUSI STEP %d (%s)", g_currentStep, (g_pendingDir == 0) ? "BUY" : "SELL");
   else if(CountPositions(InpMagicBot) == 0)
      status = (InpTriggerMode == TRIGGER_CANDLE) ? "STANDBY (menunggu kotak baru)" : "STANDBY (menunggu crossing level)";
   else
      status = StringFormat("AKTIF - STEP %d/%d (Lot: %.2f)", g_currentStep, InpMaxSteps, g_currentBotLot);

   Comment(StringFormat(
      "===========================================\n"
      "  MESIN UANG (SIMPLE)\n"
      "===========================================\n"
      " Simbol   : %s\n"
      " Status   : %s\n"
      " Jarak TP : +%s\n"
      " Jarak SL : -%s\n"
      " Magic ID : %I64d\n"
      "===========================================",
      _Symbol, status,
      DoubleToString(InpTargetDistance, g_digits),
      DoubleToString(InpTargetDistance, g_digits),
      InpMagicBot
   ));
}
//+------------------------------------------------------------------+
