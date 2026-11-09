//+------------------------------------------------------------------+
//|                                           Mesin Uang.mq5         |
//|  Mesin Uang v7 - Reverse Martingale tanpa hedge (SO ya SO)       |
//|  Pemicu GT/Crossing, Auto Lot, ATR, Filter, Statistik Live       |
//|                                      https://sagu.pages.dev      |
//+------------------------------------------------------------------+
#property copyright   "Mochamad Tabrani & Antigravity AI"
#property link        "https://sagu.pages.dev"
#property version     "7.00"
#property description "Mesin Uang Advanced: Reverse Martingale tanpa hedge, pemicu ganda, dashboard statistik"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| [1] Enum & Parameter Input                                       |
//+------------------------------------------------------------------+
enum ENUM_TRIGGER_MODE
{
   TRIGGER_CANDLE   = 0,   // Candle: close kotak naik = BUY, turun = SELL
   TRIGGER_CROSSING = 1    // Crossing level angka bulat
};

enum ENUM_DIST_MODE
{
   DIST_FIXED = 0,         // Jarak SL tetap
   DIST_ATR   = 1          // Jarak SL mengikuti ATR
};

enum ENUM_RR_MODE
{
   RR_1_1   = 0,           // 1:1 (SL 1, TP 1)
   RR_1_2   = 1,           // 1:2 (SL 1, TP 2)
   RR_1_3   = 2,           // 1:3 (SL 1, TP 3)
   RR_CUSTOM = 3           // Kustom (isi pengali TP di bawah)
};

input group "=== STRATEGI UTAMA ==="
input bool              InpEnableBot       = true;            // Aktifkan Mesin Uang Otomatis?
input ENUM_TRIGGER_MODE InpTriggerMode     = TRIGGER_CANDLE;  // Pemicu entri siklus baru
input ENUM_TIMEFRAMES   InpTriggerTF       = PERIOD_M1;       // Timeframe kotak (mode Candle)
input double            InpPriceInterval   = 1.0;             // Jarak level angka bulat (mode Crossing)
input double            InpStartLot        = 0.01;            // Lot Dasar Awal (Step 1)
input double            InpLotMultiplier   = 2.0;             // Faktor Pengali Martingale
input int               InpMaxSteps        = 6;               // Step maks (lot berhenti naik, tetap balik arah). 0 = tanpa batas

input group "=== JARAK TP & SL ==="
input ENUM_RR_MODE      InpRRMode          = RR_1_1;          // Rasio SL : TP
input double            InpCustomRR        = 1.5;             // Pengali TP terhadap SL (jika rasio Kustom)
input ENUM_DIST_MODE    InpDistMode        = DIST_FIXED;      // Mode jarak SL
input double            InpTargetDistance  = 1.0;             // Jarak SL tetap (harga); TP = jarak SL x rasio
input ENUM_TIMEFRAMES   InpATRTF           = PERIOD_M5;       // Timeframe ATR (mode ATR)
input int               InpATRPeriod       = 14;              // Periode ATR
input double            InpATRMultiplier   = 1.0;             // Pengali ATR untuk jarak TP/SL

input group "=== AUTO LOT (OPSIONAL) ==="
input bool              InpAutoLot         = false;           // Lot awal mengikuti saldo?
input double            InpAutoLotBase     = 0.01;            // Lot per kelipatan saldo
input double            InpAutoLotEvery    = 100.0;           // Kelipatan saldo (mata uang akun)

input group "=== FILTER ENTRI SIKLUS BARU (OPSIONAL) ==="
input bool              InpUseTrendFilter  = false;           // Hanya entri searah EMA?
input ENUM_TIMEFRAMES   InpTrendTF         = PERIOD_M5;       // Timeframe EMA
input int               InpTrendMAPeriod   = 50;              // Periode EMA
input int               InpMaxSpreadPts    = 0;               // Spread maks (poin), 0 = nonaktif
input bool              InpUseTimeFilter   = false;           // Filter jam server?
input int               InpStartHour       = 0;               // Jam mulai (0-23)
input int               InpEndHour         = 24;              // Jam selesai (1-24)
input double            InpDailyTargetPct  = 0.0;             // Stop siklus baru bila untung harian >= % (0 = nonaktif)
input double            InpDailyLossPct    = 0.0;             // Stop siklus baru bila rugi harian >= % (0 = nonaktif)

input group "=== NOTIFIKASI & BROKER ==="
input bool              InpEnableAlert     = true;            // Popup Alert di Layar MT5?
input bool              InpEnablePush      = false;           // Notifikasi ke HP (MetaQuotes ID)?
input bool              InpVerbose         = true;            // Catat alasan entri dilewati di tab Experts?
input int               InpSlippage        = 50;              // Toleransi Slippage (pts)
input long              InpMagicBot        = 888100;          // Magic Number Khusus Bot Ini

//+------------------------------------------------------------------+
//| [2] Variabel Global                                              |
//+------------------------------------------------------------------+
CTrade            g_trade;
double            g_point;
int               g_digits;
string            g_gvPrefix;

int               g_currentStep     = 1;
double            g_currentBotLot   = 0.01;
ulong             g_lastManagedDeal = 0;
double            g_lastPrice       = 0.0;
double            g_lastDist        = 0.0;
datetime          g_lastBarTime     = 0;

int               g_pendingDir      = -1;    // -1 tidak ada, 0 BUY, 1 SELL
int               g_failCount       = 0;
uint              g_lastTryMs       = 0;

int               g_hATR            = INVALID_HANDLE;
int               g_hMA             = INVALID_HANDLE;

int               g_dayStamp        = 0;
double            g_dayStartEquity  = 0.0;

int               g_cntTP           = 0;
int               g_cntSL           = 0;
int               g_maxStepReached  = 1;
double            g_sessionNet      = 0.0;

//+------------------------------------------------------------------+
//| [3] Lifecycle                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpLotMultiplier < 1.0 || InpMaxSteps < 0 || InpPriceInterval <= 0.0 ||
      InpTargetDistance <= 0.0 || InpStartLot <= 0.0)
   {
      Print("Mesin Uang: parameter tidak valid. Periksa lot, pengali, step, interval, dan jarak TP/SL.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   g_point    = _Point;
   g_digits   = _Digits;
   g_gvPrefix = StringFormat("MU_%s_%I64d_", _Symbol, InpMagicBot);

   g_trade.SetExpertMagicNumber(InpMagicBot);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(GetOptimalFilling(_Symbol));

   if(InpDistMode == DIST_ATR)
   {
      g_hATR = iATR(_Symbol, InpATRTF, InpATRPeriod);
      if(g_hATR == INVALID_HANDLE)
         Print("Mesin Uang: ATR gagal dibuat, jarak TP/SL memakai nilai tetap.");
   }
   if(InpUseTrendFilter)
   {
      g_hMA = iMA(_Symbol, InpTrendTF, InpTrendMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_hMA == INVALID_HANDLE)
         Print("Mesin Uang: EMA gagal dibuat, filter tren dinonaktifkan.");
   }

   g_currentStep   = 1;
   g_currentBotLot = CalcStartLot();
   g_pendingDir    = -1;
   g_lastPrice     = 0.0;
   g_lastBarTime   = 0;

   if(!MQLInfoInteger(MQL_TESTER))
      LoadState();

   g_dayStamp       = DayStamp(TimeCurrent());
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   SaveState();

   Print("=== Mesin Uang Advanced v7.00 Aktif ===");
   UpdateChartComment();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(g_hATR != INVALID_HANDLE) IndicatorRelease(g_hATR);
   if(g_hMA  != INVALID_HANDLE) IndicatorRelease(g_hMA);
   if(MQLInfoInteger(MQL_TESTER)) GlobalVariablesDeleteAll(g_gvPrefix);
   Comment("");
   Print("=== Mesin Uang Dihentikan ===");
}

//+------------------------------------------------------------------+
//| [4] Eksekusi Tiap Tick                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateDay();

   if(InpEnableBot)
   {
      if(g_pendingDir >= 0)
         ProcessPending();
      else if(InpTriggerMode == TRIGGER_CANDLE)
         CheckCandleTrigger();
      else
         CheckDirectionalCrossing();
   }
   else if(g_pendingDir >= 0)
   {
      g_pendingDir    = -1;
      g_currentStep   = 1;
      g_currentBotLot = CalcStartLot();
      SaveState();
      Print("Bot dinonaktifkan saat order lanjutan menunggu: siklus direset ke Step 1.");
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

   if(CountPositions(InpMagicBot) > 0) return;

   double o = iOpen(_Symbol, InpTriggerTF, 1);
   double c = iClose(_Symbol, InpTriggerTF, 1);

   if(c == o)
   {
      if(InpVerbose) Print("Kotak doji (open = close): tidak entri.");
      return;
   }

   bool isBuy = (c > o);
   string why = BlockReason(isBuy);
   if(why != "")
   {
      if(InpVerbose) Print(StringFormat("Kotak %s dilewati: %s.", isBuy ? "naik" : "turun", why));
      return;
   }

   Print(StringFormat("[KOTAK %s] Open %.*f Close %.*f -> %s",
         isBuy ? "NAIK" : "TURUN", g_digits, o, g_digits, c, isBuy ? "BUY" : "SELL"));
   OpenBotOrder(isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, g_currentBotLot);
}

//+------------------------------------------------------------------+
//| [5b] Pemicu Crossing Level Angka Bulat                           |
//+------------------------------------------------------------------+
void CheckDirectionalCrossing()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(CountPositions(InpMagicBot) > 0)
   {
      g_lastPrice = bid;
      return;
   }

   if(g_lastPrice <= 0.0)
   {
      g_lastPrice = bid;
      return;
   }

   double step = InpPriceInterval;

   double levelUp = MathFloor(bid / step) * step;
   if(g_lastPrice < levelUp && bid >= levelUp)
   {
      g_lastPrice = bid;
      string why = BlockReason(true);
      if(why != "")
      {
         if(InpVerbose) Print(StringFormat("Crossing naik %.2f dilewati: %s.", levelUp, why));
         return;
      }
      Print(StringFormat("[CROSSING BUY] Melintas naik level %.2f", levelUp));
      OpenBotOrder(POSITION_TYPE_BUY, g_currentBotLot);
      return;
   }

   double levelDown = MathCeil(bid / step) * step;
   if(g_lastPrice > levelDown && bid <= levelDown)
   {
      g_lastPrice = bid;
      string why = BlockReason(false);
      if(why != "")
      {
         if(InpVerbose) Print(StringFormat("Crossing turun %.2f dilewati: %s.", levelDown, why));
         return;
      }
      Print(StringFormat("[CROSSING SELL] Melintas turun level %.2f", levelDown));
      OpenBotOrder(POSITION_TYPE_SELL, g_currentBotLot);
      return;
   }

   g_lastPrice = bid;
}

//+------------------------------------------------------------------+
//| [6] Filter Entri Siklus Baru                                     |
//+------------------------------------------------------------------+
string BlockReason(bool isBuy)
{
   if(!SpreadOK())     return "spread melebihi batas";
   if(!InTradingHours()) return "di luar jam trading";
   string d = DailyBlock();
   if(d != "")         return d;
   if(!TrendOK(isBuy)) return "melawan tren EMA";
   return "";
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

bool TrendOK(bool isBuy)
{
   if(!InpUseTrendFilter || g_hMA == INVALID_HANDLE) return true;
   double ma[];
   ArraySetAsSeries(ma, true);
   if(CopyBuffer(g_hMA, 0, 0, 1, ma) != 1) return true;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return isBuy ? (bid > ma[0]) : (bid < ma[0]);
}

string DailyBlock()
{
   if(g_dayStartEquity <= 0.0) return "";
   double pct = (AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartEquity) / g_dayStartEquity * 100.0;
   if(InpDailyTargetPct > 0.0 && pct >= InpDailyTargetPct) return "target untung harian tercapai";
   if(InpDailyLossPct   > 0.0 && pct <= -InpDailyLossPct) return "batas rugi harian tercapai";
   return "";
}

void UpdateDay()
{
   int today = DayStamp(TimeCurrent());
   if(today != g_dayStamp)
   {
      g_dayStamp       = today;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   }
}

int DayStamp(datetime t)
{
   MqlDateTime d;
   TimeToStruct(t, d);
   return d.year * 10000 + d.mon * 100 + d.day;
}

//+------------------------------------------------------------------+
//| [7] Order Lanjutan (Martingale / Searah)                         |
//+------------------------------------------------------------------+
// Coba buka langsung; kalau gagal, antrikan dan coba lagi di OnTick
void StartOrQueue(ENUM_POSITION_TYPE type)
{
   g_failCount = 0;
   if(!InpEnableBot)
   {
      g_pendingDir = -1;
      SaveState();
      return;
   }

   if(OpenBotOrder(type, g_currentBotLot))
      g_pendingDir = -1;
   else
      g_pendingDir = (type == POSITION_TYPE_BUY) ? 0 : 1;
   SaveState();
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
      SaveState();
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
      g_currentBotLot = CalcStartLot();
      SaveState();
   }
}

//+------------------------------------------------------------------+
//| [8] Transaksi: Kalibrasi & Reverse Martingale                    |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong dealTicket = trans.deal;
   if(dealTicket == 0 || !HistoryDealSelect(dealTicket)) return;

   long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);

   // Deposit / penarikan: sesuaikan patokan equity harian
   if(dealType == DEAL_TYPE_BALANCE)
   {
      g_dayStartEquity += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      return;
   }

   string sym   = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   long   magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(sym != _Symbol || magic != InpMagicBot) return;

   long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

   if(dealEntry == DEAL_ENTRY_IN)
   {
      ulong  posTicket  = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      double exactPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
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
                 + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                 + HistoryDealGetDouble(dealTicket, DEAL_FEE);
   g_sessionNet += net;

   ENUM_POSITION_TYPE origType = (dealType == DEAL_TYPE_SELL) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

   if(reason == DEAL_REASON_TP)
   {
      g_cntTP++;
      string msg = StringFormat("[STEP %d TP] Hasil bersih %.2f. Reset ke Step 1, lanjut searah.", g_currentStep, net);
      Print(msg);
      if(InpEnableAlert) Alert(msg);

      g_currentStep   = 1;
      g_currentBotLot = CalcStartLot();
      StartOrQueue(origType);
   }
   else if(reason == DEAL_REASON_SL)
   {
      g_cntSL++;
      int slStep = g_currentStep;

      bool capped = (InpMaxSteps > 0 && g_currentStep >= InpMaxSteps);
      if(!capped)
      {
         g_currentStep++;
         g_currentBotLot = NormalizeLotSize(g_currentBotLot * InpLotMultiplier);
      }
      if(g_currentStep > g_maxStepReached) g_maxStepReached = g_currentStep;

      string msg = capped
         ? StringFormat("[STEP %d SL] Hasil bersih %.2f. Step maks: lot ditahan %.2f, balik arah.", slStep, net, g_currentBotLot)
         : StringFormat("[STEP %d SL] Hasil bersih %.2f. Balik arah ke Step %d (Lot %.2f).", slStep, net, g_currentStep, g_currentBotLot);
      Print(msg);
      if(InpEnableAlert) Alert(msg);
      if(InpEnablePush && capped) SendNotification(msg);

      StartOrQueue((origType == POSITION_TYPE_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY);
   }
   else
   {
      // Stop out / ditutup manual: jangan lanjutkan rantai
      string why = (reason == DEAL_REASON_SO) ? "STOP OUT oleh broker" : "ditutup manual/sebab lain";
      string msg = StringFormat("Posisi %s (hasil bersih %.2f). Siklus direset ke Step 1.", why, net);
      Print(msg);
      if(InpEnableAlert) Alert(msg);
      if(InpEnablePush)  SendNotification(msg);

      g_pendingDir    = -1;
      g_currentStep   = 1;
      g_currentBotLot = CalcStartLot();
      SaveState();
   }
}

//+------------------------------------------------------------------+
//| [9] Kalibrasi TP/SL Pasca-Eksekusi                               |
//+------------------------------------------------------------------+
void CalibratePositionTPSL(ulong posTicket, double exactPrice, ENUM_POSITION_TYPE posType)
{
   if(!PositionSelectByTicket(posTicket)) return;

   double dist    = (g_lastDist > 0.0) ? g_lastDist : InpTargetDistance;
   double tpDist  = dist * GetRR();
   double exactTP = (posType == POSITION_TYPE_BUY) ? (exactPrice + tpDist) : (exactPrice - tpDist);
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
//| [10] Eksekutor Order                                             |
//+------------------------------------------------------------------+
double GetBaseDist()
{
   if(InpDistMode == DIST_ATR && g_hATR != INVALID_HANDLE)
   {
      double a[];
      ArraySetAsSeries(a, true);
      if(CopyBuffer(g_hATR, 0, 1, 1, a) == 1 && a[0] > 0.0)
         return a[0] * InpATRMultiplier;
   }
   return InpTargetDistance;
}

double GetRR()
{
   switch(InpRRMode)
   {
      case RR_1_2:    return 2.0;
      case RR_1_3:    return 3.0;
      case RR_CUSTOM: return MathMax(0.1, InpCustomRR);
      default:        return 1.0;
   }
}

double GetDist()
{
   double stopLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point;
   double spread  = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double need    = stopLvl + spread + 2.0 * g_point;   // SL harus cukup jauh dari harga pasar
   return MathMax(GetBaseDist(), need);
}

bool OpenBotOrder(ENUM_POSITION_TYPE type, double lot)
{
   lot = NormalizeLotSize(lot);
   double dist = NormalizeDouble(GetDist(), g_digits);   // jarak SL
   double tpDist = dist * GetRR();                       // jarak TP
   g_lastDist  = dist;

   g_trade.SetExpertMagicNumber(InpMagicBot);
   string cmt = StringFormat("MesinUang %s S%d", (type == POSITION_TYPE_BUY) ? "BUY" : "SELL", g_currentStep);
   bool ok;

   if(type == POSITION_TYPE_BUY)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(!HasMargin(ORDER_TYPE_BUY, lot, ask)) { Print("Margin tidak cukup untuk BUY lot ", DoubleToString(lot, 2)); return false; }
      ok = g_trade.Buy(lot, _Symbol, ask, NormalizeDouble(ask - dist, g_digits), NormalizeDouble(ask + tpDist, g_digits), cmt);
   }
   else
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(!HasMargin(ORDER_TYPE_SELL, lot, bid)) { Print("Margin tidak cukup untuk SELL lot ", DoubleToString(lot, 2)); return false; }
      ok = g_trade.Sell(lot, _Symbol, bid, NormalizeDouble(bid + dist, g_digits), NormalizeDouble(bid - tpDist, g_digits), cmt);
   }

   if(!ok || !RetcodeOK(g_trade.ResultRetcode()))
   {
      Print(StringFormat("Order gagal. Kode: %u (%s)", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription()));
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| [11] Penyimpanan State (tahan restart / ganti timeframe)         |
//+------------------------------------------------------------------+
void SaveState()
{
   if(MQLInfoInteger(MQL_TESTER)) return;
   GlobalVariableSet(g_gvPrefix + "step",    (double)g_currentStep);
   GlobalVariableSet(g_gvPrefix + "lot",     g_currentBotLot);
   GlobalVariableSet(g_gvPrefix + "pending", (double)g_pendingDir);
   GlobalVariableSet(g_gvPrefix + "time",    (double)TimeCurrent());
}

void LoadState()
{
   if(!GlobalVariableCheck(g_gvPrefix + "step")) return;

   int      step = (int)GlobalVariableGet(g_gvPrefix + "step");
   double   lot  = GlobalVariableGet(g_gvPrefix + "lot");
   int      pend = (int)GlobalVariableGet(g_gvPrefix + "pending");
   datetime t    = (datetime)GlobalVariableGet(g_gvPrefix + "time");

   bool hasPos = (CountPositions(InpMagicBot) > 0);
   bool fresh  = ((TimeCurrent() - t) <= 120);

   // Pulihkan hanya bila ada posisi berjalan atau order lanjutan baru saja menunggu
   if(!hasPos && !fresh) return;
   if(step < 1 || lot <= 0.0) return;

   g_currentStep   = step;
   g_currentBotLot = NormalizeLotSize(lot);
   g_pendingDir    = (!hasPos && fresh && pend >= 0 && pend <= 1) ? pend : -1;
   if(g_currentStep > g_maxStepReached) g_maxStepReached = g_currentStep;

   Print(StringFormat("State dipulihkan: Step %d, Lot %.2f, order menunggu=%d", g_currentStep, g_currentBotLot, g_pendingDir));
}

//+------------------------------------------------------------------+
//| [12] Helper                                                      |
//+------------------------------------------------------------------+
double CalcStartLot()
{
   double lot = InpStartLot;
   if(InpAutoLot && InpAutoLotEvery > 0.0)
   {
      double units = MathFloor(AccountInfoDouble(ACCOUNT_BALANCE) / InpAutoLotEvery);
      lot = MathMax(units, 1.0) * InpAutoLotBase;
   }
   return NormalizeLotSize(lot);
}

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

double BotFloatingPL()
{
   double p = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicBot)
         p += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return p;
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
//| [13] Dashboard di Chart (murni tampilan)                         |
//+------------------------------------------------------------------+
void UpdateChartComment()
{
   static uint lastMs = 0;
   uint now = GetTickCount();
   if(now - lastMs < 500) return;
   lastMs = now;

   int posCount = CountPositions(InpMagicBot);

   string status;
   if(!InpEnableBot)
      status = "NONAKTIF";
   else if(g_pendingDir >= 0)
      status = StringFormat("MENUNGGU EKSEKUSI STEP %d (%s)", g_currentStep, (g_pendingDir == 0) ? "BUY" : "SELL");
   else if(posCount == 0)
   {
      string d = DailyBlock();
      if(d != "")
         status = "STANDBY - " + d;
      else
         status = (InpTriggerMode == TRIGGER_CANDLE) ? "STANDBY (menunggu kotak baru)" : "STANDBY (menunggu crossing level)";
   }
   else
      status = StringFormat("AKTIF - STEP %d (Lot: %.2f)", g_currentStep, g_currentBotLot);

   string stepLimit = (InpMaxSteps > 0) ? IntegerToString(InpMaxSteps) : "tanpa batas";
   string distTxt   = (InpDistMode == DIST_ATR)
                      ? StringFormat("ATR x %.2f (sekarang %s)", InpATRMultiplier, DoubleToString(GetBaseDist(), g_digits))
                      : DoubleToString(InpTargetDistance, g_digits);
   double spreadPts = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / g_point;
   double dayPct    = (g_dayStartEquity > 0.0) ? (AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartEquity) / g_dayStartEquity * 100.0 : 0.0;
   int    total     = g_cntTP + g_cntSL;
   double winRate   = (total > 0) ? (100.0 * g_cntTP / total) : 0.0;

   string s = "";
   s += "===========================================\n";
   s += "  MESIN UANG ADVANCED v7.0\n";
   s += "===========================================\n";
   s += " Simbol    : " + _Symbol + "\n";
   s += " Status    : " + status + "\n";
   s += " Pemicu    : " + ((InpTriggerMode == TRIGGER_CANDLE) ? "Candle " + EnumToString(InpTriggerTF) : "Crossing level") + "\n";
   s += " Step/Maks : " + IntegerToString(g_currentStep) + " / " + stepLimit + "\n";
   s += " Jarak SL   : " + distTxt + "\n";
   s += " Rasio     : SL 1 : TP " + DoubleToString(GetRR(), 1) + "\n";
   s += " Spread    : " + DoubleToString(spreadPts, 0) + " poin\n";
   s += "-------------------------------------------\n";
   s += " Floating  : " + DoubleToString(BotFloatingPL(), 2) + "\n";
   s += " Hari ini  : " + DoubleToString(dayPct, 2) + " %\n";
   s += " Sesi      : TP " + IntegerToString(g_cntTP) + " | SL " + IntegerToString(g_cntSL)
        + " | Win " + DoubleToString(winRate, 1) + " %\n";
   s += " Hasil sesi: " + DoubleToString(g_sessionNet, 2) + " | Step tertinggi: " + IntegerToString(g_maxStepReached) + "\n";
   s += " Magic ID  : " + IntegerToString((int)InpMagicBot) + "\n";
   s += "===========================================";
   Comment(s);
}
//+------------------------------------------------------------------+
