//+------------------------------------------------------------------+
//|                                                   MesinUang.mq5  |
//|  Mesin Uang - Directional Crossing & Reverse Martingale          |
//|  Kunci Hedge Pra-SL + State Tahan Restart + Proteksi Tambahan    |
//|                                       https://sagu.pages.dev     |
//+------------------------------------------------------------------+
#property copyright   "Mochamad Tabrani & Antigravity AI"
#property link        "https://sagu.pages.dev"
#property version     "6.00"
#property description "Mesin Uang: Zero-Level Crossing & Reverse Martingale dengan Kunci Hedge Pra-SL"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| [1] Parameter Input                                              |
//+------------------------------------------------------------------+
input group "=== PENGATURAN STRATEGI UTAMA ==="
input bool            InpEnableBot         = true;      // Aktifkan Robot Otomatis?
input double          InpStartLot          = 0.01;      // Lot Dasar Awal (Step 1)
input double          InpLotMultiplier     = 2.0;       // Faktor Pengali Martingale
input int             InpMaxSteps          = 6;         // Batas Maksimal Step Pembalikan
input double          InpPriceInterval     = 1.0;       // Jarak Level Angka Bulat Pemicu (harga)
input double          InpTargetDistance    = 1.0;       // Jarak TP & SL dari Entry (harga)
input bool            InpHedgeOnMaxStep    = true;      // Kunci Hedge 1:1 sebelum SL step terakhir?
input double          InpLockTriggerPct    = 80.0;      // Kunci aktif saat rugi mencapai % jarak SL (10-95)

input group "=== PROTEKSI TAMBAHAN ==="
input int             InpMaxSpreadPts      = 0;         // Spread maks (poin) untuk entry baru, 0 = nonaktif
input double          InpMaxDailyLossPct   = 20.0;      // Batas rugi harian (% equity awal hari), 0 = nonaktif
input bool            InpUseTimeFilter     = false;     // Filter jam untuk siklus baru (jam server)?
input int             InpStartHour         = 0;         // Jam mulai (0-23)
input int             InpEndHour           = 24;        // Jam selesai (1-24)
input int             InpMaxOrderRetries   = 5;         // Maks percobaan ulang order gagal sebelum berhenti
input int             InpResumeAfterMin    = 240;       // Auto-lanjut setelah berhenti (menit), 0 = manual
input bool            InpResetState        = false;     // Reset status tersimpan saat dipasang (kembalikan ke false)

input group "=== NOTIFIKASI & BROKER ==="
input bool            InpEnableAlert       = true;      // Popup Alert di Layar MT5?
input bool            InpEnablePush        = false;     // Notifikasi ke HP (MetaQuotes ID)?
input int             InpSlippage          = 50;        // Toleransi Slippage (pts)
input long            InpMagicBot          = 888100;    // Magic Number Bot (hedge memakai Magic + 1)

//+------------------------------------------------------------------+
//| [2] Variabel Global                                              |
//+------------------------------------------------------------------+
CTrade            g_trade;
double            g_point;
int               g_digits;
long              g_magicHedge;
string            g_gvPrefix;

int               g_currentStep     = 1;
double            g_currentBotLot   = 0.01;
bool              g_isHalted        = false;
int               g_haltReason      = 0;      // 1=kunci hedge, 2=step maks SL/gagal order/stop out, 3=rugi harian
datetime          g_haltTime        = 0;
int               g_pendingDir      = -1;     // -1 tidak ada, 0 BUY, 1 SELL (order lanjutan yang menunggu)
int               g_failCount       = 0;
uint              g_lastTryMs       = 0;
uint              g_lastLockMs      = 0;
ulong             g_lastManagedDeal = 0;
double            g_lastPrice       = 0.0;
double            g_lastDist        = 0.0;
bool              g_canHedge        = true;

ulong             g_calibTicket     = 0;
double            g_calibPrice      = 0.0;
ENUM_POSITION_TYPE g_calibType      = POSITION_TYPE_BUY;
int               g_calibTries      = 0;

int               g_dayStamp        = 0;
double            g_dayStartEquity  = 0.0;

//+------------------------------------------------------------------+
//| [3] Lifecycle                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpMaxSteps < 1 || InpLotMultiplier < 1.0 || InpPriceInterval <= 0.0 ||
      InpTargetDistance <= 0.0 || InpStartLot <= 0.0)
   {
      Print("Mesin Uang: parameter tidak valid. Periksa lot, pengali, step, interval, dan jarak TP/SL.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   g_point      = _Point;
   g_digits     = _Digits;
   g_magicHedge = InpMagicBot + 1;
   g_gvPrefix   = StringFormat("MU_%s_%I64d_", _Symbol, InpMagicBot);

   g_trade.SetExpertMagicNumber(InpMagicBot);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(GetOptimalFilling(_Symbol));

   // Kunci hedge butuh akun hedging; di akun netting posisi lawan justru menutup posisi utama
   g_canHedge = true;
   if(InpHedgeOnMaxStep &&
      AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      g_canHedge = false;
      Print("Mesin Uang: akun bukan tipe HEDGING, kunci hedge dinonaktifkan. Step maks kena SL akan menghentikan bot.");
   }

   ResetChain();
   if(!InpResetState && !MQLInfoInteger(MQL_TESTER))
      LoadState();

   g_lastPrice = 0.0;
   SaveState();

   Print("=== Mesin Uang v6.00 Aktif ===");
   UpdateChartComment();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Comment("");
   if(MQLInfoInteger(MQL_TESTER))
      GlobalVariablesDeleteAll(g_gvPrefix);
   Print("=== Mesin Uang Dihentikan ===");
}

//+------------------------------------------------------------------+
//| [4] Eksekusi Tiap Tick                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckDailyLoss();
   CheckResume();
   ProcessCalibration();
   CheckPreSLLock();

   if(!InpEnableBot)
   {
      if(g_pendingDir >= 0)
      {
         g_pendingDir = -1;
         ResetChain();
         SaveState();
         Print("Bot dinonaktifkan saat ada order lanjutan menunggu: siklus direset ke Step 1.");
      }
   }
   else if(!g_isHalted)
   {
      if(g_pendingDir >= 0) ProcessPending();
      else                  CheckDirectionalCrossing();
   }

   UpdateChartComment();
}

//+------------------------------------------------------------------+
//| [5] Pemicu: Crossing Level Angka Bulat                           |
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

   double step    = InpPriceInterval;
   bool   allowed = (SpreadOK() && InTradingHours());

   // Crossing NAIK -> BUY
   double levelUp = MathFloor(bid / step) * step;
   if(g_lastPrice < levelUp && bid >= levelUp)
   {
      g_lastPrice = bid;
      if(!allowed) return;
      Print(StringFormat("[CROSSING BUY] Melintas naik level %.2f", levelUp));
      OpenBotOrder(POSITION_TYPE_BUY, g_currentBotLot);
      return;
   }

   // Crossing TURUN -> SELL
   double levelDown = MathCeil(bid / step) * step;
   if(g_lastPrice > levelDown && bid <= levelDown)
   {
      g_lastPrice = bid;
      if(!allowed) return;
      Print(StringFormat("[CROSSING SELL] Melintas turun level %.2f", levelDown));
      OpenBotOrder(POSITION_TYPE_SELL, g_currentBotLot);
      return;
   }

   g_lastPrice = bid;
}

//+------------------------------------------------------------------+
//| [6] Order Lanjutan (Martingale / Searah) - dieksekusi di OnTick  |
//+------------------------------------------------------------------+
void ProcessPending()
{
   if(CountPositions(InpMagicBot) > 0) return;
   if(!SpreadOK()) return;

   uint now = GetTickCount();
   if(now - g_lastTryMs < 1000) return;
   g_lastTryMs = now;

   ENUM_POSITION_TYPE t = (g_pendingDir == 0) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

   if(OpenBotOrder(t, g_currentBotLot))
   {
      g_pendingDir = -1;
      g_failCount  = 0;
      g_lastPrice  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      SaveState();
   }
   else
   {
      g_failCount++;
      Print(StringFormat("Order lanjutan gagal (percobaan %d/%d).", g_failCount, InpMaxOrderRetries));
      if(g_failCount >= InpMaxOrderRetries)
         HaltBot(2, StringFormat("[BERHENTI] Order Step %d gagal terus. Periksa margin/koneksi.", g_currentStep));
   }
}

//+------------------------------------------------------------------+
//| [7] Transaksi: Pencatatan Hasil Posisi                           |
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
   if(sym != _Symbol || magic != InpMagicBot) return;   // posisi hedge (magic+1) diabaikan

   long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   long dealType  = HistoryDealGetInteger(dealTicket, DEAL_TYPE);

   // Posisi baru terisi: jadwalkan kalibrasi TP/SL (dikerjakan di OnTick)
   if(dealEntry == DEAL_ENTRY_IN)
   {
      g_calibTicket = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      g_calibPrice  = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      g_calibType   = (dealType == DEAL_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      g_calibTries  = 0;
      return;
   }

   // Posisi tertutup
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
                 + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                 + HistoryDealGetDouble(dealTicket, DEAL_FEE);

   if(g_isHalted)
   {
      Print(StringFormat("Posisi tertutup saat bot berhenti. Hasil bersih: %.2f", net));
      return;
   }

   // Arah posisi asli (deal penutup berlawanan arah dengan posisi)
   ENUM_POSITION_TYPE origType = (dealType == DEAL_TYPE_SELL) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

   if(reason == DEAL_REASON_TP)
   {
      string msg = StringFormat("[STEP %d TP] Hasil bersih: %.2f. Reset ke Step 1, lanjut searah.", g_currentStep, net);
      Print(msg);
      if(InpEnableAlert) Alert(msg);

      g_currentStep   = 1;
      g_currentBotLot = InpStartLot;
      g_failCount     = 0;
      g_pendingDir    = (origType == POSITION_TYPE_BUY) ? 0 : 1;
      SaveState();
   }
   else if(reason == DEAL_REASON_SL)
   {
      if(g_currentStep >= InpMaxSteps)
      {
         HaltBot(2, StringFormat("[STEP %d SL] Step maksimal kena SL (hasil bersih %.2f). Bot berhenti.", g_currentStep, net));
         return;
      }

      g_currentStep++;
      g_currentBotLot = NormalizeLotSize(g_currentBotLot * InpLotMultiplier);
      g_failCount     = 0;
      g_pendingDir    = (origType == POSITION_TYPE_BUY) ? 1 : 0;   // balik arah

      string msg = StringFormat("[STEP %d SL] Hasil bersih: %.2f. Balik arah ke Step %d (Lot %.2f).",
                                g_currentStep - 1, net, g_currentStep, g_currentBotLot);
      Print(msg);
      if(InpEnableAlert) Alert(msg);
      SaveState();
   }
   else if(reason == DEAL_REASON_SO)
   {
      HaltBot(2, "[STOP OUT] Posisi ditutup paksa broker. Bot berhenti.");
   }
   else
   {
      // Ditutup manual / sebab lain: jangan lanjutkan rantai martingale
      Print(StringFormat("Posisi ditutup bukan oleh TP/SL (hasil bersih %.2f). Siklus direset ke Step 1.", net));
      ResetChain();
      SaveState();
   }
}

//+------------------------------------------------------------------+
//| [8] Kalibrasi TP/SL Pasca-Eksekusi (dengan cek hasil)            |
//+------------------------------------------------------------------+
void ProcessCalibration()
{
   if(g_calibTicket == 0) return;

   if(!PositionSelectByTicket(g_calibTicket))
   {
      g_calibTicket = 0;
      return;
   }

   double dist    = (g_lastDist > 0.0) ? g_lastDist : InpTargetDistance;
   double exactTP = (g_calibType == POSITION_TYPE_BUY) ? g_calibPrice + dist : g_calibPrice - dist;
   double exactSL = (g_calibType == POSITION_TYPE_BUY) ? g_calibPrice - dist : g_calibPrice + dist;
   exactTP = NormalizeDouble(exactTP, g_digits);
   exactSL = NormalizeDouble(exactSL, g_digits);

   double curTP = PositionGetDouble(POSITION_TP);
   double curSL = PositionGetDouble(POSITION_SL);

   if(MathAbs(curTP - exactTP) <= g_point * 0.1 && MathAbs(curSL - exactSL) <= g_point * 0.1)
   {
      g_calibTicket = 0;
      return;
   }

   g_trade.SetExpertMagicNumber(InpMagicBot);
   if(g_trade.PositionModify(g_calibTicket, exactSL, exactTP) && RetcodeOK(g_trade.ResultRetcode()))
   {
      Print(StringFormat("[KALIBRASI] Tiket #%I64u | Entry %.*f | TP %.*f | SL %.*f",
                         g_calibTicket, g_digits, g_calibPrice, g_digits, exactTP, g_digits, exactSL));
      g_calibTicket = 0;
   }
   else
   {
      g_calibTries++;
      if(g_calibTries >= 5)
      {
         Print(StringFormat("Kalibrasi tiket #%I64u gagal (kode %u), TP/SL awal dipertahankan.",
                            g_calibTicket, g_trade.ResultRetcode()));
         g_calibTicket = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| [9] Eksekutor Order                                              |
//+------------------------------------------------------------------+
double GetDist()
{
   double stopLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point;
   double spread  = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double need    = stopLvl + spread + 2.0 * g_point;   // SL harus cukup jauh dari harga pasar
   return MathMax(InpTargetDistance, need);
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
      double tp = NormalizeDouble(ask + dist, g_digits);
      double sl = NormalizeDouble(ask - dist, g_digits);
      ok = g_trade.Buy(lot, _Symbol, ask, sl, tp, cmt);
   }
   else
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(!HasMargin(ORDER_TYPE_SELL, lot, bid)) { Print("Margin tidak cukup untuk SELL lot ", DoubleToString(lot, 2)); return false; }
      double tp = NormalizeDouble(bid - dist, g_digits);
      double sl = NormalizeDouble(bid + dist, g_digits);
      ok = g_trade.Sell(lot, _Symbol, bid, sl, tp, cmt);
   }

   if(!ok || !RetcodeOK(g_trade.ResultRetcode()))
   {
      Print(StringFormat("Order gagal. Kode: %u (%s)", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription()));
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| [10] Kunci Hedge 1:1 SEBELUM SL Step Terakhir                    |
//+------------------------------------------------------------------+
void CheckPreSLLock()
{
   if(!InpHedgeOnMaxStep || !g_canHedge || g_isHalted) return;
   if(g_currentStep < InpMaxSteps) return;

   ulong ticket = GetBotPositionTicket();
   if(ticket == 0 || !PositionSelectByTicket(ticket)) return;

   double sl = PositionGetDouble(POSITION_SL);
   if(sl <= 0.0) return;

   double open   = PositionGetDouble(POSITION_PRICE_OPEN);
   double vol    = PositionGetDouble(POSITION_VOLUME);
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

   // Lepas SL/TP posisi utama agar tidak terjadi realisasi sepihak yang meninggalkan hedge telanjang
   g_calibTicket = 0;
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

   HaltBot(1, StringFormat("[KUNCI HEDGE 1:1] Step %d terkunci (lot %.2f). Tutup kedua posisi secara manual.", g_currentStep, hedgeLot));
}

//+------------------------------------------------------------------+
//| [11] Berhenti / Lanjut / Batas Rugi Harian                       |
//+------------------------------------------------------------------+
void HaltBot(int reason, string msg)
{
   g_isHalted    = true;
   g_haltReason  = reason;
   g_haltTime    = TimeCurrent();
   g_pendingDir  = -1;

   Print(msg);
   if(InpEnableAlert) Alert(msg);
   if(InpEnablePush)  SendNotification(msg);
   SaveState();
}

void CheckResume()
{
   if(!g_isHalted) return;

   int total = CountPositions(InpMagicBot) + CountPositions(g_magicHedge);
   if(total > 0) return;

   bool resume = false;
   if(g_haltReason == 1)
      resume = true;                                                // operator sudah menutup semua posisi
   else if(g_haltReason == 3)
      resume = (DayStamp(TimeCurrent()) != DayStamp(g_haltTime));   // lanjut di hari berikutnya
   else if(InpResumeAfterMin > 0)
      resume = ((TimeCurrent() - g_haltTime) >= (datetime)(InpResumeAfterMin * 60));

   if(resume)
   {
      ResetChain();
      g_lastPrice = 0.0;
      SaveState();
      Print("Siklus direset. Mesin Uang aktif kembali di Step 1.");
   }
}

void CheckDailyLoss()
{
   int today = DayStamp(TimeCurrent());
   if(today != g_dayStamp)
   {
      g_dayStamp       = today;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      SaveState();
   }

   if(InpMaxDailyLossPct <= 0.0 || g_isHalted || g_dayStartEquity <= 0.0) return;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= g_dayStartEquity * (1.0 - InpMaxDailyLossPct / 100.0))
      HaltBot(3, StringFormat("[BATAS RUGI HARIAN] Equity %.2f turun %.1f%% dari awal hari. Bot berhenti sampai besok.",
                              eq, InpMaxDailyLossPct));
}

void ResetChain()
{
   g_isHalted      = false;
   g_haltReason    = 0;
   g_currentStep   = 1;
   g_currentBotLot = NormalizeLotSize(InpStartLot);
   g_pendingDir    = -1;
   g_failCount     = 0;
}

//+------------------------------------------------------------------+
//| [12] Penyimpanan State (tahan restart / ganti timeframe)         |
//+------------------------------------------------------------------+
void SaveState()
{
   if(MQLInfoInteger(MQL_TESTER)) return;
   GlobalVariableSet(g_gvPrefix + "step",     (double)g_currentStep);
   GlobalVariableSet(g_gvPrefix + "halted",   g_isHalted ? 1.0 : 0.0);
   GlobalVariableSet(g_gvPrefix + "reason",   (double)g_haltReason);
   GlobalVariableSet(g_gvPrefix + "haltTime", (double)g_haltTime);
   GlobalVariableSet(g_gvPrefix + "pending",  (double)g_pendingDir);
   GlobalVariableSet(g_gvPrefix + "dayStamp", (double)g_dayStamp);
   GlobalVariableSet(g_gvPrefix + "dayEq",    g_dayStartEquity);
}

void LoadState()
{
   if(!GlobalVariableCheck(g_gvPrefix + "step")) return;

   int step = (int)GlobalVariableGet(g_gvPrefix + "step");
   if(step < 1 || step > InpMaxSteps) step = 1;

   g_currentStep   = step;
   g_currentBotLot = NormalizeLotSize(InpStartLot * MathPow(InpLotMultiplier, step - 1));
   g_isHalted      = (GlobalVariableGet(g_gvPrefix + "halted") > 0.5);
   g_haltReason    = (int)GlobalVariableGet(g_gvPrefix + "reason");
   g_haltTime      = (datetime)GlobalVariableGet(g_gvPrefix + "haltTime");
   g_pendingDir    = (int)GlobalVariableGet(g_gvPrefix + "pending");
   g_dayStamp      = (int)GlobalVariableGet(g_gvPrefix + "dayStamp");
   g_dayStartEquity= GlobalVariableGet(g_gvPrefix + "dayEq");

   if(g_pendingDir < -1 || g_pendingDir > 1) g_pendingDir = -1;
   Print(StringFormat("State dipulihkan: Step %d, Lot %.2f, Berhenti=%s, Menunggu order=%d",
                      g_currentStep, g_currentBotLot, g_isHalted ? "ya" : "tidak", g_pendingDir));
}

//+------------------------------------------------------------------+
//| [13] Helper                                                      |
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

bool SpreadOK()
{
   if(InpMaxSpreadPts <= 0) return true;
   double spreadPts = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / g_point;
   return (spreadPts <= InpMaxSpreadPts);
}

bool InTradingHours()
{
   if(!InpUseTimeFilter) return true;
   MqlDateTime d;
   TimeToStruct(TimeCurrent(), d);
   if(InpStartHour <= InpEndHour)
      return (d.hour >= InpStartHour && d.hour < InpEndHour);
   return (d.hour >= InpStartHour || d.hour < InpEndHour);
}

int DayStamp(datetime t)
{
   MqlDateTime d;
   TimeToStruct(t, d);
   return d.year * 10000 + d.mon * 100 + d.day;
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
   if(stepLot <= 0.0) stepLot = 0.01;

   int dig = 0;
   double s = stepLot;
   while(dig < 8 && MathAbs(s - MathRound(s)) > 1e-8) { s *= 10.0; dig++; }

   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);
   return NormalizeDouble(MathRound(lot / stepLot) * stepLot, dig);
}

//+------------------------------------------------------------------+
//| [14] Status di Chart (murni tampilan, tanpa efek samping)        |
//+------------------------------------------------------------------+
void UpdateChartComment()
{
   string status;
   if(!InpEnableBot)
      status = "NONAKTIF";
   else if(g_isHalted)
   {
      if(g_haltReason == 1)      status = "TERKUNCI HEDGE 1:1 (tutup posisi manual untuk lanjut)";
      else if(g_haltReason == 3) status = "BERHENTI - batas rugi harian (lanjut besok)";
      else                       status = "BERHENTI - step maks SL / order gagal / stop out";
   }
   else if(g_pendingDir >= 0)
      status = StringFormat("MENUNGGU EKSEKUSI STEP %d (%s)", g_currentStep, (g_pendingDir == 0) ? "BUY" : "SELL");
   else if(CountPositions(InpMagicBot) == 0)
      status = "STANDBY (menunggu crossing level)";
   else
      status = StringFormat("AKTIF - STEP %d/%d (Lot: %.2f)", g_currentStep, InpMaxSteps, g_currentBotLot);

   int distPts = (int)MathRound(InpTargetDistance / g_point);

   Comment(StringFormat(
      "===========================================\n"
      "  MESIN UANG v6.00\n"
      "===========================================\n"
      " Simbol   : %s\n"
      " Status   : %s\n"
      " Jarak TP : +%s (%d poin)\n"
      " Jarak SL : -%s (%d poin)\n"
      " Magic ID : %I64d (hedge: %I64d)\n"
      "===========================================",
      _Symbol, status,
      DoubleToString(InpTargetDistance, g_digits), distPts,
      DoubleToString(InpTargetDistance, g_digits), distPts,
      InpMagicBot, g_magicHedge
   ));
}
//+------------------------------------------------------------------+
